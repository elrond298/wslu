# wslu - Windows 10 linux Subsystem Utility
# wslview-helper.ps1 - resident launcher for wslview
# <https://github.com/wslutilities/wslu>
#
# wslview starts this on demand and talks to it over a loopback TCP socket, so
# that each wslview call does not pay for a fresh powershell.exe plus a fresh
# Shell.Application COM object. See docs/wslview.1 for the whole picture.
#
# Protocol: one request per connection, fields separated by a TAB, terminated
# by a LF. TAB is the separator because it cannot occur in a token or an action,
# and a TAB inside the payload is preserved (the split stops after 3 fields):
#
#     <token> <TAB> <action> <TAB> <payload> <LF>
#
#     open      ShellExecute the payload through the shell association
#     explorer  run explorer.exe on the payload
#     reveal    run explorer.exe /select,<payload>
#     ping      liveness check, no side effect
#     quit      make the helper exit
#
# Reply: a single line, "OK", "FAIL", or "ERR <reason>".
#
# Notes for whoever changes this next:
#   * Windows PowerShell 5.1 only. No inline `if` expressions, no ternary.
#   * The port is published to -PortFile, which wslview passes as a
#     \\wsl.localhost\ UNC path into the wslu state directory. wslview deletes that
#     file before starting this helper, so the file existing means a helper bound
#     and published itself. Do not go back to letting wslview choose the port: the
#     loopback port space is shared with the Linux side in mirrored networking mode
#     and a collision is silent from wslview's side.
#   * The token is passed on the command line on purpose. It only has to keep
#     unrelated local sockets from reaching the launcher, and anything that can
#     read this process's command line can read the state directory anyway.
#   * The listener is loopback only. That is enough in WSL mirrored networking
#     mode; in NAT mode WSL cannot reach the Windows loopback at all, so
#     wslview falls back to launching powershell.exe and this helper is simply
#     never used. Add a -BindAddress for the vEthernet (WSL) address in here and
#     in src/wslview.sh if NAT mode ever needs it.
#   * A request must never be able to kill the helper: every failure path still
#     writes a reply, otherwise wslview sits in `read -t` until it times out.

param(
	[Parameter(Mandatory = $true)][string]$PortFile,
	[Parameter(Mandatory = $true)][string]$Token,
	[int]$IdleSeconds = 7200
)

$ErrorActionPreference = 'Stop'

# Bind an ephemeral port and publish it, instead of taking a port from wslview.
# Windows keeps reserved port ranges that netstat does not report, and in WSL
# mirrored networking mode the loopback port space is shared with the Linux side,
# so a port picked by wslview can already belong to an unrelated listener. If
# wslview guessed, it would connect to that stranger, hand it the token, and
# never learn that this helper had failed to bind.
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
[System.IO.File]::WriteAllText($PortFile, "$($listener.LocalEndpoint.Port)`n")

# Built once. This is the entire point of the helper.
$shell = New-Object -ComObject Shell.Application

$running = $true
$idle = 0
$pollMicroseconds = 5000000

while ($running) {
	if (-not $listener.Server.Poll($pollMicroseconds, [System.Net.Sockets.SelectMode]::SelectRead)) {
		# nothing arrived within the poll window; give up after IdleSeconds so an
		# unused helper does not sit in the process list forever
		$idle += $pollMicroseconds
		if ($idle -ge ($IdleSeconds * 1000000)) { break }
		continue
	}
	$idle = 0

	$client = $listener.AcceptTcpClient()
	$reply = 'ERR internal'
	try {
		$stream = $client.GetStream()
		$reader = New-Object System.IO.StreamReader($stream)
		$line = $reader.ReadLine()
		if ($null -eq $line) { $line = '' }

		$fields = $line -split "`t", 3
		if ($fields.Count -ne 3) {
			$reply = 'ERR request'
		} elseif ($fields[0] -ne $Token) {
			$reply = 'ERR token'
		} else {
			$payload = $fields[2]
			try {
				switch ($fields[1]) {
					'ping' { $reply = 'OK' }
					'open' { $shell.ShellExecute($payload); $reply = 'OK' }
					'explorer' { & explorer.exe $payload; $reply = 'OK' }
					'reveal' { & explorer.exe "/select,$payload"; $reply = 'OK' }
					'quit' { $reply = 'OK'; $running = $false }
					default { $reply = 'ERR action' }
				}
			} catch {
				$reply = 'FAIL'
			}
		}

		# ponytail: StreamReader/StreamWriter per connection costs ~3ms of the
		# ~68ms call. Switch to Socket.Receive/Send with a byte buffer if that
		# ever matters.
		$writer = New-Object System.IO.StreamWriter($stream)
		$writer.AutoFlush = $true
		# LF only. The default is Environment.NewLine, which is CRLF on Windows, and
		# the trailing CR makes every reply fail the `case` match on the bash side.
		$writer.NewLine = "`n"
		$writer.WriteLine($reply)
		$writer.Dispose()
	} catch {
		# a broken client must not take the helper down
	} finally {
		$client.Close()
	}
}

$listener.Stop()
