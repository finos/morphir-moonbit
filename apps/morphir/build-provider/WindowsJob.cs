using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// The job handle is never inherited. Closing this worker, including an abrupt
// termination, kills its job. No breakaway flags are enabled. The root starts
// suspended and joins the job before any model code can create descendants.
public static class MorphirWindowsJob
{
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount,
            ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits
    {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [StructLayout(LayoutKind.Sequential)] struct Accounting
    {
        public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
        public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct Startup
    {
        public uint Size;
        public string Reserved, Desktop, Title;
        public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
        public ushort ShowWindow, Reserved2Size;
        public IntPtr Reserved2, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo
    {
        public IntPtr Process, Thread;
        public uint ProcessId, ThreadId;
    }
    public sealed class Receipt
    {
        public string profile = "morphir-windows-job-v1";
        public bool terminated = true;
        public int pid;
        public int exitCode;
        public string reason;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting accounting, uint size, IntPtr length);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CreateProcessW(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref Startup startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr sourceProcess, IntPtr source, IntPtr targetProcess, out IntPtr target, uint access, bool inherit, uint options);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GetStdHandle(int kind);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr attributes, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    static long Now() { return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalMilliseconds; }
    static bool Exited(IntPtr handle)
    {
        uint state = WaitForSingleObject(handle, 0);
        if (state == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error());
        return state == 0;
    }
    static string StopReason(IntPtr owner, long deadline, string stop)
    {
        if (File.Exists(stop)) return "execution.cancelled";
        if (Exited(owner)) return "execution.owner_exited";
        if (Now() >= deadline) return "execution.deadline";
        return "";
    }
    // Microsoft CRT argv quoting, including empty args, quotes and trailing '\'.
    static string Quote(string argument)
    {
        if (argument == null || argument.IndexOf('\0') >= 0) throw new ArgumentException("Invalid argument");
        var value = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in argument)
        {
            if (c == '\\') { slashes++; continue; }
            value.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            value.Append(c); slashes = 0;
        }
        value.Append('\\', slashes * 2).Append('"');
        return value.ToString();
    }
    static IntPtr InheritedStandardHandle(int kind)
    {
        IntPtr original = GetStdHandle(kind), temporary = IntPtr.Zero, duplicate;
        try
        {
            if (original == IntPtr.Zero || original == new IntPtr(-1))
            {
                temporary = CreateFileW("NUL", kind == -10 ? 0x80000000u : 0x40000000u, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
                Check(temporary != new IntPtr(-1)); original = temporary;
            }
            Check(DuplicateHandle(GetCurrentProcess(), original, GetCurrentProcess(), out duplicate, 0, true, 2));
            return duplicate;
        }
        finally { if (temporary != IntPtr.Zero && temporary != new IntPtr(-1)) CloseHandle(temporary); }
    }
    public static Receipt Run(string program, string[] arguments, string directory, string[] environment, IntPtr owner, long deadline, string stop)
    {
        var receipt = new Receipt { pid = 0, exitCode = -1, reason = StopReason(owner, deadline, stop) };
        if (receipt.reason != "") return receipt;
        IntPtr job = IntPtr.Zero;
        IntPtr environmentBlock = IntPtr.Zero;
        var process = new ProcessInfo();
        var startup = new Startup { Size = (uint)Marshal.SizeOf(typeof(Startup)), Flags = 0x100 };
        bool assigned = false;
        try
        {
            job = CreateJobObjectW(IntPtr.Zero, null); Check(job != IntPtr.Zero);
            var limits = new ExtendedLimits(); limits.Basic.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
            Check(SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits))));
            startup.Input = InheritedStandardHandle(-10);
            startup.Output = InheritedStandardHandle(-11);
            startup.Error = InheritedStandardHandle(-12);
            var command = new StringBuilder(Quote(program));
            foreach (string argument in arguments) command.Append(' ').Append(Quote(argument));
            if (command.Length > 32766) throw new ArgumentException("Command line limit");
            environmentBlock = Marshal.StringToHGlobalUni(string.Join("\0", environment) + "\0\0");
            receipt.reason = StopReason(owner, deadline, stop);
            if (receipt.reason != "") return receipt;
            Check(CreateProcessW(program, command, IntPtr.Zero, IntPtr.Zero, true, 0x08000404, environmentBlock, directory, ref startup, out process));
            receipt.pid = unchecked((int)process.ProcessId);
            Check(AssignProcessToJobObject(job, process.Process)); assigned = true;
            Check(ResumeThread(process.Thread) != 0xffffffff);
            while (!Exited(process.Process))
            {
                receipt.reason = StopReason(owner, deadline, stop);
                if (receipt.reason != "") break;
                Thread.Sleep(10);
            }
            if (receipt.reason == "") { uint code; Check(GetExitCodeProcess(process.Process, out code)); receipt.exitCode = unchecked((int)code); }
            // Normal parent exit is also a cleanup boundary. Its descendants may
            // still have inherited pipes open or be running with closed stdio.
            Check(TerminateJobObject(job, 1));
            long cleanupDeadline = Now() + 1000;
            while (true)
            {
                Accounting accounting;
                Check(QueryInformationJobObject(job, 1, out accounting, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero));
                if (accounting.ActiveProcesses == 0) break;
                if (Now() >= cleanupDeadline) throw new TimeoutException("Job termination unconfirmed");
                Thread.Sleep(5);
            }
            return receipt;
        }
        finally
        {
            if (process.Process != IntPtr.Zero && !assigned)
            {
                // Assignment failed while still suspended. It cannot have children.
                TerminateProcess(process.Process, 1); WaitForSingleObject(process.Process, 1000);
            }
            if (job != IntPtr.Zero) CloseHandle(job);
            if (process.Thread != IntPtr.Zero) CloseHandle(process.Thread);
            if (process.Process != IntPtr.Zero) CloseHandle(process.Process);
            if (startup.Input != IntPtr.Zero) CloseHandle(startup.Input);
            if (startup.Output != IntPtr.Zero) CloseHandle(startup.Output);
            if (startup.Error != IntPtr.Zero) CloseHandle(startup.Error);
            if (environmentBlock != IntPtr.Zero) Marshal.FreeHGlobal(environmentBlock);
        }
    }
}
