/*
    Runs inside After Effects. Same shape as hello-premiere.jsx.

    Remember trap 2: if Premiere Pro is running, BridgeTalk may hand this to the
    After Effects engine *inside* Premiere, where it will report success and change
    nothing you can see. The runner refuses to start in that case.
*/
(function () {
    var out = [];
    function say(key, value) { out.push(key + "\t" + value); }
    function probe(key, fn) {
        try { say(key, String(fn())); } catch (e) { say(key + "_ERROR", e.toString()); }
    }

    probe("version", function () { return app.version; });
    probe("project", function () { return app.project.file ? app.project.file.name : "(unsaved)"; });
    probe("items", function () { return app.project.numItems; });
    probe("activeItem", function () {
        return app.project.activeItem ? app.project.activeItem.name : "(none)";
    });
    // Proves we are in After Effects proper and not Premiere's embedded engine.
    probe("buildName", function () { return app.buildName; });

    // Set by the runner before the job runs; falls back to the job's own folder.
    var workDir = ($.global.ASR_WORKDIR)
        ? String($.global.ASR_WORKDIR)
        : String(File($.fileName).parent.fsName).split(String.fromCharCode(92)).join("/");
    var report = new File(workDir + "/hello-aftereffects_report.txt");
    report.encoding = "UTF-8";
    report.open("w");
    report.write(out.join("\n"));
    report.close();

    return "VERDICT: OK aftereffects " + app.version;
})();
