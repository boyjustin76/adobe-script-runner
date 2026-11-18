using System;
using System.Collections;
using System.Runtime.InteropServices;
using System.Text;
public static class NativeDummy {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Startup { public int cb; public string reserved, desktop, title; public int x,y,xs,ys,xc,yc,fill,flags; public short show,reserved2; public IntPtr reservedPtr,input,output,error; }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process,thread; public int pid,tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref Startup si, out ProcessInfo pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static int Start(string executable, bool omit) {
        var vars = new System.Collections.Generic.SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(DictionaryEntry item in Environment.GetEnvironmentVariables()) vars[(string)item.Key]=(string)item.Value;
        foreach(string key in new[]{"CommonProgramFiles","CommonProgramFiles(x86)","CommonProgramW6432"}) vars[key]="C:\\Common";
        if(omit) foreach(string key in new[]{"CommonProgramFiles","CommonProgramFiles(x86)","CommonProgramW6432"}) vars.Remove(key);
        vars["PRIVATE_TEST_SENTINEL"]="never-print-this-value";
        var block=new StringBuilder(); foreach(var item in vars) block.Append(item.Key).Append('=').Append(item.Value).Append('\0'); block.Append('\0');
        IntPtr env=Marshal.StringToHGlobalUni(block.ToString());
        try {
            var si=new Startup(); si.cb=Marshal.SizeOf(typeof(Startup)); ProcessInfo pi;
            if(!CreateProcess(executable,new StringBuilder("\""+executable+"\" -n 120 127.0.0.1"),IntPtr.Zero,IntPtr.Zero,false,0x08000400,env,null,ref si,out pi))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(pi.thread); CloseHandle(pi.process); return pi.pid;
        } finally {Marshal.FreeHGlobal(env);}
    }
}
