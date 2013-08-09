import std.stdio;
import std.path;
import std.datetime;
import std.string;

import ae.sys.windows;
import ae.utils.time;
import win32.windows;
import win32.tlhelp32;

void main(string[] args)
{
	static struct ProcessInfo
	{
		string exeName;
		HANDLE h;
		FILETIME kernelTime;
		FILETIME userTime;

		void updateTimes()
		{
			FILETIME dummy;
			GetProcessTimes(h, &dummy, &dummy, &kernelTime, &userTime);
		}
	}

	ProcessInfo[DWORD] processInfo;

	ProcessWatcher watcher;
	FILETIME lastTime;

	int maxExeLength;

	while (true)
	{
		void newProcessHandler(ref PROCESSENTRY32 pe)
		{
			auto exeName = pe.szExeFile[].fromWString();
			bool matches = args.length == 1;
			foreach (mask; args[1..$])
				if (exeName.globMatch(mask))
				{
					matches = true;
					break;
				}

			if (matches)
			{
				auto h = OpenProcess(PROCESS_QUERY_INFORMATION, false, pe.th32ProcessID);
				if (!h)
					return;

				if (maxExeLength < exeName.length)
					maxExeLength = exeName.length;

				auto pi = ProcessInfo(exeName, h);
				pi.updateTimes();
				processInfo[pe.th32ProcessID] = pi;
			}
		}

		void removedProcessHandler(ref PROCESSENTRY32 pe)
		{
			if (pe.th32ProcessID in processInfo)
			{
				CloseHandle(processInfo[pe.th32ProcessID].h);
				processInfo.remove(pe.th32ProcessID);
			}
		}

		watcher.update(&removedProcessHandler, &newProcessHandler, true);

		FILETIME time;
		GetSystemTimeAsFileTime(&time);
		auto delta = makeUlong(time.tupleof) - makeUlong(lastTime.tupleof);
		auto timeStr = formatTime("H:i:s", FILETIMEToSysTime(cast(core.sys.windows.windows.FILETIME*)&time, UTC()));

	    CONSOLE_SCREEN_BUFFER_INFO csbi;
	    GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi);
	    auto width = csbi.dwSize.X;

		foreach (ref pi; processInfo)
		{
			auto next = pi;
			next.updateTimes();
			auto kernelDelta = makeUlong(next.kernelTime.tupleof) - makeUlong(pi.kernelTime.tupleof);
			auto   userDelta = makeUlong(next.  userTime.tupleof) - makeUlong(pi.  userTime.tupleof);
			auto kernelFraction = cast(real)kernelDelta / delta;
			auto   userFraction = cast(real)  userDelta / delta;

			auto str = format("[%s] %-*s %5.2f%% [", timeStr, maxExeLength, pi.exeName, (kernelFraction+userFraction)*100);
			auto barWidth = width - str.length - 2;
			auto kernelEnd = cast(int)(kernelFraction * barWidth);
			auto userEnd   = cast(int)(  userFraction * barWidth) + kernelEnd;

			foreach (n; 0..barWidth)
				if (n < kernelEnd)
					str ~= "K";
				else
				if (n < userEnd)
					str ~= "U";
				else
					str ~= ".";
			str ~= "]";
			writeln(str);	

			pi = next;
		}

		if (processInfo.length > 1)
			writeln();

		lastTime = time;

		sleepUntilNextSecond();
	}
}

// avoid drift; don't busyloop or use arbitrary fixed intervals
void sleepUntilNextSecond()
{
	auto now = GetTickCount();
	auto nextSecond = (GetTickCount() / 1000 + 1) * 1000;
	do
	{
		Sleep(nextSecond - now);
		now = GetTickCount();
	}
	while (now < nextSecond);
}
