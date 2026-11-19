/*  The wrapper for the *direct* transport.

    After Effects can be told to run a script at startup:

        AfterFX.exe -r C:\work\direct.jsx

    No Photoshop, no BridgeTalk, no COM. That matters for one reason: the relay
    refuses an After Effects job while Premiere Pro is open, because BridgeTalk
    would deliver it to the After Effects engine *inside* Premiere (trap 2). The
    direct transport has no such ambiguity -- it starts its own After Effects.

    What this file is for: `-r` throws the job's return value away. The runner's
    whole protocol is the verdict line, so something has to catch it and write it
    down. The runner copies this file into the work directory and points After
    Effects at the copy, so "the folder I am in" is the answer to "where do I
    write?" -- the same trick bridge.jsx uses, for the same reason: there is
    nowhere to pass an argument.

    It also quits After Effects itself, cleanly. Killing After Effects instead
    leaves it convinced it crashed, and the next launch sits on a recovery dialog
    that blocks every script, invisibly (trap 5). One force-kill costs you the
    next run.
*/
(function () {
    var here = String(File($.fileName).parent.fsName).split(String.fromCharCode(92)).join("/");

    function read(path) {
        var f = new File(path);
        if (!f.exists) { return ""; }
        f.encoding = "UTF-8";
        f.open("r");
        var text = f.read();
        f.close();
        // A BOM becomes part of the string and silently corrupts any path read from it.
        return text.replace(/^\uFEFF/, "");
    }
    function write(path, text) {
        var f = new File(path);
        f.encoding = "UTF-8";
        f.open("w");
        f.write(text);
        f.close();
    }
    function trim(s) { return String(s).replace(/^\s+|\s+$/g, ""); }

    var result = "VERDICT: FAIL direct wrapper did not run";

    /*  -NewInstance: the runner started a separate After Effects ('-m') and handed
        it a one-time token. If the token is missing or different, this script landed
        in somebody else's After Effects. Touch nothing, quit nothing; say so.  */
    var expected = trim(read(here + "/_token.txt"));
    if (expected && trim($.getenv("ASR_INSTANCE_TOKEN") || "") !== expected) {
        try { write(here + "/_result.txt", "VERDICT: FAIL wrong-instance: job reached an After Effects this runner did not start; nothing was done"); } catch (e0) {}
        return;
    }

    /*  Startup is over once this line runs: After Effects has read its preferences.
        The runner holds the start/stop gate until it sees this file (trap 20).  */
    var gated = !!expected;
    if (gated) { try { write(here + "/_started.txt", "1"); } catch (e1) {} }

    try {
        var jobPath = trim(read(here + "/_job.txt"));
        if (!jobPath) {
            result = "VERDICT: FAIL _job.txt missing or empty";
        } else if (!(new File(jobPath)).exists) {
            result = "VERDICT: FAIL job not found: " + jobPath;
        } else {
            /*  Same contract as the relay: the job may write anything it wants the
                caller to read into ASR_WORKDIR. Its presence is also how a job knows
                not to quit the app -- this wrapper does that, after the result is on
                disk. A job that quits first leaves you with no verdict and no clue.  */
            $.global.ASR_WORKDIR = here;
            var returned;
            try {
                returned = $.evalFile(new File(jobPath));
            } catch (jobError) {
                returned = "JOBERR " + jobError.toString() + " @line " + jobError.line;
            }
            result = String(returned);
        }
    } catch (e) {
        result = "VERDICT: FAIL direct wrapper: " + e.toString();
    }

    /*  A job that leaves unsaved changes makes After Effects ask "save changes?" on
        the way out, and nobody is there to answer (trap 21). In an instance of our
        own, say so in the result and drop the changes: saving is the job's business.  */
    var discard = false;
    if (gated) { try { discard = !!app.project.dirty; } catch (eD) {} }
    if (discard) { result += "\nWARN unsaved-changes-discarded: the job left the project modified; closed without saving"; }

    try { write(here + "/_result.txt", result); } catch (e2) {}

    /*  Quitting rewrites the preferences folder, and every After Effects shares that
        folder (trap 20). So an instance of ours does not quit until the runner,
        holding the start/stop gate, says so by creating _quit_ok.txt. If the runner
        has gone away, quit anyway after ten minutes rather than stay open for ever.

        Wait with a scheduled task, not with a loop. A loop keeps this script alive,
        After Effects puts up its "running script" window, and a quit called from
        there closed the project, showed the Home screen and stopped: the process
        stayed for ever and refused every polite request to close (2 instances in 8,
        2026-11-19). With the wait moved to a scheduled task, 21 instances in 21 quit
        by themselves the same day. Why the loop version stalled is still a guess.  */
    function leave() {
        if (discard) { try { app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES); } catch (eC) {} }
        /*  Quit, and quit politely. See the note at the top of this file. */
        try { app.quit(); } catch (e3) {}
    }
    if (!gated) { leave(); return; }

    var askedAt = new Date().getTime();
    $.global.__asrLeave = function () {
        if ((new File(here + "/_quit_ok.txt")).exists || (new Date().getTime() - askedAt) > 600000) {
            try { app.cancelTask($.global.__asrLeaveTask); } catch (eT) {}
            leave();
        }
    };
    $.global.__asrLeaveTask = app.scheduleTask("$.global.__asrLeave()", 500, true);
})();
