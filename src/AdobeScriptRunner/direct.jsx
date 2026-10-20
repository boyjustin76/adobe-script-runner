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

    try { write(here + "/_result.txt", result); } catch (e2) {}

    /*  Quit, and quit politely. See the note at the top of this file. */
    try { app.quit(); } catch (e3) {}
})();
