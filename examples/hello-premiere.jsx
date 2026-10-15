/*
    A job, in the shape every job should have.

    Runs inside Premiere Pro. Reports what it found, and ends with a verdict line.

    The verdict line is the contract. The runner does not trust the return value,
    because ExtendScript returns the last expression it evaluated even when the
    script fell over three lines earlier -- and BridgeTalk reports that as a
    successful round trip. A job says for itself whether it worked.
*/
(function () {
    var out = [];
    function say(key, value) { out.push(key + "\t" + value); }
    function probe(key, fn) {
        try { say(key, String(fn())); } catch (e) { say(key + "_ERROR", e.toString()); }
    }

    probe("version", function () { return app.version; });
    probe("project", function () { return app.project ? app.project.name : "(none open)"; });
    probe("sequences", function () { return app.project ? app.project.sequences.numSequences : 0; });
    probe("activeSequence", function () {
        return app.project && app.project.activeSequence
            ? app.project.activeSequence.name : "(none)";
    });

    // Write the detail somewhere the caller can read it afterwards. The runner also
    // captures whatever this function returns, but a file survives a timeout.
    //
    // ASR_WORKDIR is set by the runner before the job runs. Falling back to the
    // job's own folder keeps this script usable when run by hand.
    var workDir = ($.global.ASR_WORKDIR)
        ? String($.global.ASR_WORKDIR)
        : String(File($.fileName).parent.fsName).split(String.fromCharCode(92)).join("/");
    var report = new File(workDir + "/hello-premiere_report.txt");
    report.encoding = "UTF-8";
    report.open("w");
    report.write(out.join("\n"));
    report.close();

    // Last line, and the only thing the runner judges on.
    return "VERDICT: OK premiere " + app.version;
})();
