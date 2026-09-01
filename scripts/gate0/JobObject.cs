using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Apf.Gate0
{
    public sealed class FileIdentityResult
    {
        public string Path { get; set; }
        public string FinalPath { get; set; }
        public uint VolumeSerialNumber { get; set; }
        public ulong FileId { get; set; }
        public uint LinkCount { get; set; }
        public bool IsReparsePoint { get; set; }
    }

    public static class FileIdentity
    {
        private const uint FILE_READ_ATTRIBUTES = 0x00000080;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes;
            public FILETIME CreationTime;
            public FILETIME LastAccessTime;
            public FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFileAttributes(string fileName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(
            IntPtr file,
            out BY_HANDLE_FILE_INFORMATION information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(
            IntPtr file,
            StringBuilder path,
            uint pathLength,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static FileIdentityResult Inspect(string path)
        {
            uint pathAttributes = GetFileAttributes(path);
            if (pathAttributes == 0xFFFFFFFF)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileAttributes failed: " + path);
            IntPtr handle = CreateFile(
                path,
                FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS,
                IntPtr.Zero);
            if (handle == new IntPtr(-1))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFile for identity failed: " + path);
            try
            {
                BY_HANDLE_FILE_INFORMATION information;
                if (!GetFileInformationByHandle(handle, out information))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed: " + path);
                StringBuilder finalPath = new StringBuilder(32768);
                uint length = GetFinalPathNameByHandle(handle, finalPath, (uint)finalPath.Capacity, 0);
                if (length == 0 || length >= finalPath.Capacity)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandle failed: " + path);
                return new FileIdentityResult
                {
                    Path = path,
                    FinalPath = finalPath.ToString(),
                    VolumeSerialNumber = information.VolumeSerialNumber,
                    FileId = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow,
                    LinkCount = information.NumberOfLinks,
                    IsReparsePoint = (pathAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0
                };
            }
            finally
            {
                CloseHandle(handle);
            }
        }
    }

    public sealed class DrainResult
    {
        public long TotalBytes { get; set; }
        public byte[] Captured { get; set; }
        public bool Truncated { get; set; }
    }

    public sealed class BrokerRunResult
    {
        public int ProcessId { get; set; }
        public long ProcessStartUtcTicks { get; set; }
        public int ExitCode { get; set; }
        public bool TimedOut { get; set; }
        public bool JobTerminated { get; set; }
        public string TerminationMode { get; set; }
        public long DurationMs { get; set; }
        public DrainResult Stdout { get; set; }
        public DrainResult Stderr { get; set; }
    }

    public static class Broker
    {
        private const uint JOB_OBJECT_LIMIT_ACTIVE_PROCESS = 0x00000008;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JobObjectExtendedLimitInformation = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public IntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        private static IntPtr CreateConfiguredJob(int activeProcessLimit)
        {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed");

            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            limits.BasicLimitInformation.LimitFlags =
                JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_ACTIVE_PROCESS;
            limits.BasicLimitInformation.ActiveProcessLimit = (uint)activeProcessLimit;

            int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(limits, buffer, false);
                if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, buffer, (uint)size))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject failed");
            }
            catch
            {
                CloseHandle(job);
                throw;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
            return job;
        }

        private static DrainResult Drain(Stream stream, int captureLimit)
        {
            byte[] buffer = new byte[8192];
            MemoryStream captured = new MemoryStream();
            long total = 0;
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                total += read;
                int remaining = captureLimit - (int)captured.Length;
                if (remaining > 0)
                {
                    int keep = Math.Min(remaining, read);
                    captured.Write(buffer, 0, keep);
                }
            }
            return new DrainResult
            {
                TotalBytes = total,
                Captured = captured.ToArray(),
                Truncated = total > captureLimit
            };
        }

        public static BrokerRunResult Run(
            string executable,
            string arguments,
            string workingDirectory,
            IDictionary<string, string> environment,
            int stdoutCaptureLimit,
            int stderrCaptureLimit,
            int waitMs,
            string terminationMode,
            int activeProcessLimit)
        {
            if (terminationMode != "none" && terminationMode != "terminate" && terminationMode != "close")
                throw new ArgumentException("terminationMode must be none, terminate or close");

            IntPtr job = CreateConfiguredJob(activeProcessLimit);
            Process process = new Process();
            Stopwatch stopwatch = Stopwatch.StartNew();
            Task<DrainResult> stdoutTask = null;
            Task<DrainResult> stderrTask = null;
            try
            {
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = executable;
                start.Arguments = arguments;
                start.WorkingDirectory = workingDirectory;
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                start.RedirectStandardInput = true;
                start.RedirectStandardOutput = true;
                start.RedirectStandardError = true;
                start.StandardOutputEncoding = Encoding.UTF8;
                start.StandardErrorEncoding = Encoding.UTF8;
                start.EnvironmentVariables.Clear();
                foreach (KeyValuePair<string, string> pair in environment)
                    start.EnvironmentVariables[pair.Key] = pair.Value;

                process.StartInfo = start;
                if (!process.Start())
                    throw new InvalidOperationException("Process.Start returned false");

                BrokerRunResult result = new BrokerRunResult();
                result.ProcessId = process.Id;
                result.ProcessStartUtcTicks = process.StartTime.ToUniversalTime().Ticks;
                result.TerminationMode = terminationMode;

                stdoutTask = Task<DrainResult>.Factory.StartNew(
                    delegate { return Drain(process.StandardOutput.BaseStream, stdoutCaptureLimit); },
                    CancellationToken.None,
                    TaskCreationOptions.LongRunning,
                    TaskScheduler.Default);
                stderrTask = Task<DrainResult>.Factory.StartNew(
                    delegate { return Drain(process.StandardError.BaseStream, stderrCaptureLimit); },
                    CancellationToken.None,
                    TaskCreationOptions.LongRunning,
                    TaskScheduler.Default);

                if (!AssignProcessToJobObject(job, process.Handle))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed");

                process.StandardInput.WriteLine("GO");
                process.StandardInput.Flush();
                process.StandardInput.Close();

                if (terminationMode == "none")
                {
                    if (!process.WaitForExit(waitMs))
                    {
                        result.TimedOut = true;
                        if (!TerminateJobObject(job, 0xE0000001))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateJobObject after timeout failed");
                        result.JobTerminated = true;
                    }
                }
                else
                {
                    Thread.Sleep(waitMs);
                    if (terminationMode == "terminate")
                    {
                        if (!TerminateJobObject(job, 0xE0000002))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateJobObject failed");
                    }
                    else
                    {
                        if (!CloseHandle(job))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "CloseHandle(job) failed");
                        job = IntPtr.Zero;
                    }
                    result.JobTerminated = true;
                }

                process.WaitForExit(5000);
                Task.WaitAll(new Task[] { stdoutTask, stderrTask }, 5000);
                result.ExitCode = process.HasExited ? process.ExitCode : -1;
                result.Stdout = stdoutTask.IsCompleted ? stdoutTask.Result : new DrainResult();
                result.Stderr = stderrTask.IsCompleted ? stderrTask.Result : new DrainResult();
                stopwatch.Stop();
                result.DurationMs = stopwatch.ElapsedMilliseconds;
                return result;
            }
            finally
            {
                if (job != IntPtr.Zero)
                    CloseHandle(job);
                process.Dispose();
            }
        }
    }
}
