/*
    Runs inside the relay app (Photoshop or Illustrator).

    Reads the job path from <workdir>/_job.txt, sends "run that file" to the target
    app over BridgeTalk, and writes whatever comes back to <workdir>/_result.txt.

    Why a relay at all: Premiere Pro and After Effects publish no COM automation
    ProgID on Windows, so PowerShell cannot talk to them directly. They do accept
    BridgeTalk, and Photoshop does have a ProgID. Photoshop is a postbox.

    DoJavaScriptFile passes no arguments, so there is nowhere to put a work
    directory. The runner copies this file *into* the work directory and executes
    the copy, which makes "the folder I am in" the answer.
*/

function readFile(path) {
    var f = new File(path);
    if (!f.exists) { throw new Error("not found: " + path); }
    f.encoding = "UTF-8";
    f.open("r");
    var text = f.read();
    f.close();
    // A BOM becomes part of the string and silently corrupts any path read from it.
    return text.replace(/^﻿/, "");
}

function writeFile(path, text) {
    var f = new File(path);
    f.encoding = "UTF-8";
    f.open("w");
    f.write(text);
    f.close();
}

function trim(s) { return String(s).replace(/^\s+|\s+$/g, ""); }

var workDir = String(File($.fileName).parent.fsName).split(String.fromCharCode(92)).join("/");
var jobPath = trim(readFile(workDir + "/_job.txt"));
var targetApp = trim(readFile(workDir + "/_target.txt"));
var resultFile = workDir + "/_result.txt";

/*  Resolve the target specifier rather than hard-coding a version.
    getSpecifier("premierepro") returns something like "premierepro-26.0" when the
    app is installed, and null when it is not. Hard-coding the version works right
    up until the next annual release.  */
var specifier = null;
var available = [];
try { available = BridgeTalk.getTargets(null) || []; } catch (e) { available = []; }
try { specifier = BridgeTalk.getSpecifier(targetApp); } catch (e2) { specifier = null; }

if (!specifier) {
    writeFile(resultFile,
        "VERDICT: FAIL no BridgeTalk target for '" + targetApp + "'\n" +
        "targets seen: " + available.join(", ") + "\n" +
        "The app is probably not installed, or has never been launched on this machine.");
    "FAIL no target";
} else {
    /*  Send a path, never the source.

        Escapes are processed again in transit: a literal "\t" written inside a job
        string arrived at the target as a real tab and executed as one. Telling the
        target to read the file off disk sidesteps that entirely, and keeps the
        message far below any BridgeTalk size limit.  */
    /*  $.global.ASR_WORKDIR tells the job where to leave anything it wants the
        caller to read. Without it a job can only see its own folder, which is
        wherever the job happens to live -- fine for one script, useless for a
        pipeline that writes reports.  */
    var body =
        '$.global.ASR_WORKDIR = "' + workDir + '";' +
        ' var __r; try { __r = $.evalFile(new File("' + jobPath + '")); }' +
        ' catch (e) { __r = "JOBERR " + e.toString() + " @line " + e.line; } __r;';

    var bt = new BridgeTalk();
    bt.target = specifier;
    bt.body = body;

    var answered = false;
    var reply = "";
    bt.onResult = function (message) { answered = true; reply = String(message.body); };
    bt.onError = function (message) { answered = true; reply = "BTERROR " + String(message.body); };
    bt.send();

    /*  Pump the message loop until the target answers. BridgeTalk drops the
        connection on its own after roughly 70 seconds if the target never replies,
        at which point onError fires and we fall out of this loop.  */
    while (!answered) { BridgeTalk.pump(); $.sleep(100); }

    writeFile(resultFile, reply);
    reply;
}
