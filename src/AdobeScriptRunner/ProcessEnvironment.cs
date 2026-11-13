using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace AdobeScriptRunner {
    // Read-only, Windows x64. These private PEB offsets are deliberately isolated:
    // Windows may change them. Unsupported/unreadable processes fail closed.
    public static class ProcessEnvironment {
        [StructLayout(LayoutKind.Sequential)]
        struct BasicInfo { public IntPtr Reserved, Peb, R1, R2, Pid, R3; }
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool ReadProcessMemory(IntPtr h, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool IsWow64Process(IntPtr h, out bool wow64);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("ntdll.dll")]
        static extern int NtQueryInformationProcess(IntPtr h, int cls, ref BasicInfo info, int size, out int returned);

        static byte[] Read(IntPtr h, IntPtr address, int size) {
            var buffer = new byte[size]; IntPtr read;
            if (!ReadProcessMemory(h, address, buffer, (IntPtr)size, out read) || read.ToInt64()!=size)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Environment memory read failed");
            return buffer;
        }
        public static Dictionary<string,string> GetRequired(int pid) {
            if (IntPtr.Size != 8 || !Environment.Is64BitOperatingSystem)
                throw new PlatformNotSupportedException("Use 64-bit Windows PowerShell");
            var h = OpenProcess(0x410, false, pid); // QUERY_INFORMATION | VM_READ
            if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot inspect process");
            try {
                bool wow64;
                if (!IsWow64Process(h, out wow64)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if (wow64) throw new PlatformNotSupportedException("32-bit target is unsupported");
                BasicInfo info = new BasicInfo(); int returned;
                if (NtQueryInformationProcess(h, 0, ref info, Marshal.SizeOf(typeof(BasicInfo)), out returned)!=0)
                    throw new InvalidOperationException("Process basic information unavailable");
                var parameters = (IntPtr)BitConverter.ToInt64(Read(h, IntPtr.Add(info.Peb, 0x20), 8), 0);
                var env = (IntPtr)BitConverter.ToInt64(Read(h, IntPtr.Add(parameters, 0x80), 8), 0);
                if (env == IntPtr.Zero) throw new InvalidOperationException("Null environment pointer");
                var result = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                var entry = new StringBuilder();
                // Read one UTF-16 unit at a time: do not cross into an unreadable page
                // past the terminator or depend on another private EnvironmentSize offset.
                for (int offset=0; offset<4*1024*1024; offset+=2) {
                    char c = (char)BitConverter.ToUInt16(Read(h, IntPtr.Add(env, offset), 2), 0);
                    if (c != '\0') { entry.Append(c); continue; }
                    if (entry.Length == 0) return result;
                    string item = entry.ToString(); entry.Clear();
                    int eq = item.IndexOf('=');
                    if (eq<=0) continue;
                    string name = item.Substring(0, eq);
                    if (name.Equals("CommonProgramFiles", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("CommonProgramFiles(x86)", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("CommonProgramW6432", StringComparison.OrdinalIgnoreCase))
                        result[name] = item.Substring(eq+1);
                }
                throw new InvalidOperationException("Environment terminator not found within limit");
            } finally { CloseHandle(h); }
        }
    }
}
