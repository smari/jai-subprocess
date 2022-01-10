// Subprocess utilities for Jai
// Smári McCarthy <smari@ecosophy.is>

#import "POSIX";
#import "Basic";

Pipe :: [2]s32;

Subprocess :: struct {
    returnvalue         : s32  = 0xFFFFFFFF; // Default so we'll know if it hasn't updated.
    pid                 : s32;
    stdin               : Pipe;
    stdout              : Pipe;
    stderr              : Pipe;
}


subprocess_run :: (command: []string, input: string = "") -> *Subprocess {
    s := New(Subprocess);

    pipe(*s.stdout);
    pipe(*s.stderr);
    pipe(*s.stdin);

    s.pid = fork();

    if (s.pid > 0) {
        // parent process
        close(s.stdout[1]);
        close(s.stderr[1]);
        close(s.stdin[0]);
        return s;
    } else if (s.pid == 0) {
        // child process

        // Close parent's end
        close(s.stdout[0]);
        close(s.stderr[0]);
        close(s.stdin[1]);

        // Set up standard file handles
        dup2(s.stdin[0], STDIN_FILENO);
        dup2(s.stdout[1], STDOUT_FILENO);
        dup2(s.stderr[1], STDERR_FILENO);

        // Close our duplicates
        close(s.stdin[0]);
        close(s.stdout[1]);
        close(s.stderr[1]);

        // Pass correctly formatted parameter set to execvp!

        params := string_array_to_ppu8(command);
        returnvalue := execvp(to_c_string(command[0]), params);
        print("Child exiting - execvp failed with %. Command was %\n", errno(), command);
        exit(returnvalue);
    } else {
        // error forking child process
        print("error forking the child\n");
    }
    return null;
}


subprocess_write :: (s: *Subprocess, input: string) {
    // Write to STDIN on a subprocess
    print("subprocess_write not implemented.");
    assert(false);
}


subprocess_read :: subprocess_read_stdout;
subprocess_read_stdout :: inline (s: *Subprocess, maxbytes: u64 = 1000) -> string, int {
    r, e := subprocess_read_from_pipe(s.stdout[0], maxbytes);
    return r, e;
}


subprocess_read_stderr :: inline (s: *Subprocess, maxbytes: u64 = 1000) -> string, int {
    r, e := subprocess_read_from_pipe(s.stderr[0], maxbytes);
    return r, e;
}


subprocess_read_from_pipe :: (pipe: s32, maxbytes: u64 = 1000) -> string, int {
    FIONREAD :: 127; // This is missing from POSIX.jai
    ret : string;

    // TODO: Do we want this to use alloc rather than talloc?
    ret.data = talloc(xx maxbytes);
    ret.count = read(pipe, ret.data, maxbytes);
    if ret.count == -1 {
        ret.count = 0;
        return ret, errno();
    }
    return ret, 0;
}


subprocess_exited :: (s: *Subprocess) -> bool {
    ret, status := subprocess_check_status(s);
    if ret == 0 {
        // If ret is 0, no status change has occurred
        return false;
    } else {
        // It's only actually quit if it's terminated:
        if WIFEXITED(status) return true;
        if WIFSIGNALED(status) return true;
        return false;
    }
}


subprocess_running :: (s: *Subprocess) -> bool {
    ret, status := subprocess_check_status(s);
    if ret == 0 {
        // If ret is 0, no status change has occurred
        return true;
    } else {
        // It's only actually quit if it's terminated:
        if WIFEXITED(status) return false;
        if WIFSIGNALED(status) return false;
        if WIFSTOPPED(status) return false;
        return true;
    }
}


subprocess_stopped :: (s: *Subprocess) -> bool {
    ret, status := subprocess_check_status(s);
    if ret == 0 return false;
    return WIFSTOPPED(status);
}


subprocess_crashed :: (s: *Subprocess) -> bool {
    // Technically, this only checks if it dumped a core, not whether it
    // crashed -- these are related ideas, but not identical. Perhaps rename?
    ret, status := subprocess_check_status(s);
    if ret == 0 return false;
    return WCOREDUMP(status);
}


subprocess_check_status :: (s: *Subprocess) -> pid_t, s32 {
    status : s32;
    ret := waitpid(s.pid, *status, WNOHANG);
    if ret == -1 print("waitpid: error: %\n", errno()); // TODO: Probably handle this?
    s.returnvalue = ifx WIFEXITED(status) then WEXITSTATUS(status) else 0;
    return ret, status;
}


subprocess_await_exit :: (s: *Subprocess) {
    status : s32;
    ret := waitpid(s.pid, *status, 0);
    if ret == -1 print("waitpid: error: %\n", errno()); // TODO: Probably handle this?
    if WIFEXITED(status) {
        s.returnvalue = WEXITSTATUS(status);
    }
}


subprocess_run_and_return_output :: (command: []string) -> int, string, string {
    // We will return return value and output from STDOUT and STDERR
    stdout, stderr : String_Builder;

    s := subprocess_run(command);
    subprocess_await_exit(s);
    defer free(s);

    while true {
        out, err := subprocess_read_stdout(s, maxbytes=10000);
        if out.count == 0 break;
        append(*stdout, out);
    }
    while true {
        out, err := subprocess_read_stderr(s, maxbytes=10000);
        if out.count == 0 break;
        append(*stderr, out);
    }

    return s.returnvalue, builder_to_string(*stdout), builder_to_string(*stderr);
}


// This should probably exist in the standard library somehow.
string_array_to_ppu8 :: (array: []string) -> **u8 {
    params : **u8 = alloc((array.count+1) * size_of(*u8));
    for array params[it_index] = to_c_string(it);
    return params;
}
