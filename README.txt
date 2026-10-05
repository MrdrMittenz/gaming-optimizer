Gaming Optimizer - Windows 10 / 11

Right-click Start-Gaming-Optimizer.cmd > Run as administrator, using your normal
gaming account. The menu has two actions:

  1  Disable all - display the checklist, then type YES to continue
  2  Re-enable all - restore the saved settings automatically

Close the window or press Enter to exit. No apps are uninstalled. Opening the
menu does not apply changes; Disable all requires confirmation with YES.
Keep the launcher and all Gaming-*.ps1 files together in this folder.

The launcher uses a black background with cyan/magenta headings, yellow selected
actions and prompts, green completed or preserved essentials, gray skipped items,
and red errors. Checklist markers also identify each status without relying on
colour. Saved .txt reports remain plain text.

WHY THIS CAN HELP GAMING

Reducing background CPU, GPU, disk and network work can leave more resources for
games. Closing competing overlays and recording programs may reduce rendering
conflicts, interruptions and frame-time spikes. Benefits depend on hardware,
games and existing settings; this is not an FPS or external ESP guarantee.
Microsoft recommends reviewing startup/background activity for performance:
https://support.microsoft.com/en-us/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows
EA documents that multiple overlays can cause game/application issues:
https://help.ea.com/en/articles/platforms/ea-app-how-to-close-background-apps/

BEFORE ANY CHANGE

The script builds a checklist from this PC. It lists settings, startup entries,
running optional apps and reviewed services before requesting YES.
  [x] Selected action
  [=] Already configured; no new improvement claimed
  [ ] Preserved, unavailable or not automated

Only entries in that checklist are processed. Settings that change after preview
are skipped. Cancelling does not create a backup, close apps or change Windows.
Save recordings/work and end calls first: listed optional programs are terminated.

PROFILE CHECKLIST (actual availability is checked at runtime)

  [ ] Windows background recording / Game Bar capture
  [ ] Game Mode enabled; Windows suggestions reduced
  [ ] Recognized optional Run startup entries
  [ ] Selected packaged-app background activity on supported Windows editions
  [ ] Game Bar / Overwolf / RTSS helpers
  [ ] NVIDIA overlay helpers and NVIDIA App
  [ ] Discord / PTB / Canary
  [ ] Steam overlay UI helper (Steam and Steam Input stay available)
  [ ] OBS / Streamlabs / Fraps / Bandicam / Action!
  [ ] ISLC / CCleaner / Razer Cortex
  [ ] Skype / Zoom / Teams
  [ ] Fax
  [ ] Windows Media Player Network Sharing (WMPNetworkSvc)
  [ ] Downloaded Maps Manager (MapsBroker)
  [ ] Retail Demo Service (RetailDemo)
  [ ] Connected User Experiences and Telemetry (DiagTrack)
  [ ] Windows Search (WSearch)
  [ ] Print Spooler (Spooler)

Services are changed only by exact name and only when no service outside the
reviewed disable list depends on them. Unknown services and drivers are preserved.
Disabling an idle/stopped service does not establish a performance gain.
Service choices use Microsoft's descriptions; its IoT guidance is not a universal
desktop gaming preset:
https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/services

SECURITY CONTROLS REQUESTED FOR THIS PROFILE

These are user-requested compatibility changes, not proven FPS upgrades.
Disabling them exposes the PC to malware and network attacks. Some games require
security features; disabling them can prevent those games from launching.

  [ ] Defender real-time and behavior monitoring
  [ ] Defender downloaded-file and script scanning
  [ ] Defender block at first sight / cloud reporting / sample submission
  [ ] Defender potentially unwanted app blocking
  [ ] Controlled folder access / Defender network protection
  [ ] Windows Firewall - Domain, Private and Public profiles
  [ ] Windows SmartScreen policy on supported Windows editions
  [ ] Microsoft Edge SmartScreen policy
  [ ] Core isolation: Memory integrity, when not policy/firmware locked

Defender changes use supported Set-MpPreference controls only when available and
Tamper Protection is off. Missing/blocked controls are reported. A missing Defender
module does not prove that all security protection is off.
https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference

The script verifies stored settings and, for firewall profiles and Defender
real-time protection, their effective status. Blocked/overridden changes are
reported as failed. It does not stop security services or hide warnings.
https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallprofile

Memory integrity changes require a restart, including restoration. Firmware locks
and enforced policies are not bypassed. A registry preference does not prove that
memory integrity has stopped in the current session.
https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity

NOT AUTOMATED / PRESERVED

  [ ] Tamper Protection - not configurable through normal PowerShell operation
  [ ] Third-party antivirus / endpoint security
  [ ] Smart App Control, attack-surface-reduction rules and Exploit Protection
  [ ] Secure Boot, TPM, disk encryption and sign-in/credential protections
  [ ] Other core-isolation features and firmware security
  [ ] Proprietary in-app overlay toggles without supported controls
  [ ] Startup-folder shortcuts, packaged StartupTask entries and scheduled tasks

This does not switch off every Windows Security tab. Microsoft's supported
Tamper Protection controls are in Windows Security and management tools:
https://learn.microsoft.com/en-us/defender-endpoint/tamper-protection-windows-configure

Closing Discord/NVIDIA/other helpers prevents those processes running now; they
can return if an app restarts. The script does not patch overlay DLLs or modify a
loader. Steam, EA, Ubisoft, AMD and hardware/RGB overlays may still need their
in-app settings. Restart the game to unload already-loaded hooks.

KEEP AVAILABLE

  [x] Audio, microphone and audio-device software
  [x] Ethernet, Wi-Fi and network services
  [x] USB, HID, Bluetooth, controllers, mouse and keyboard
  [x] GPU/display drivers and Windows desktop rendering
  [x] Steam Input, launchers, Store, Xbox identity and Gaming Services
  [x] DirectX, Visual C++, .NET, activation and sign-in dependencies
  [x] Device profiles, fan-control utilities and Windows Update
  [x] Unknown services and loader dependencies

Service changes apply to all users. Printing (including Print to PDF), indexing
and legacy media sharing are unavailable when their services are selected.
No blanket unknown-process killer, driver removals, firmware edits or boot tweaks
are included. An unidentified external ESP cannot be compatibility-tested here.

RESTORE AND RECORDS

  %LOCALAPPDATA%\GamingOptimizer\Backups\*.clixml
  %LOCALAPPDATA%\GamingOptimizer\ActiveProfile.txt
  %LOCALAPPDATA%\GamingOptimizer\Last-checklist.txt
  %LOCALAPPDATA%\GamingOptimizer\Last-result.txt

Keep the backups. Re-enable all restores the first Disable all snapshot in the
current cycle; repeated Disable runs preserve it. Previously disabled settings
and protections remain disabled. Services regain their saved startup, delayed
start and running states. Closed apps must be reopened normally.

Conflicting later edits, missing services and blocked restores are reported;
the active backup remains until all recorded changes are restored. If a run is
interrupted, use Re-enable all. Do not delete its backup. Empty registry keys can
remain. Windows/app updates and managed policy can re-enable settings.

OPTIONAL POWERSHELL ACCESS

Use 64-bit Windows PowerShell 5.1. Actual Disable/Enable needs administrator
rights; previews do not. PowerShell 7/32-bit shells are not supported.

  .\Gaming-Optimizer.ps1 -Mode DisableAll -WhatIf
  .\Gaming-Optimizer.ps1 -Mode DisableAll
  .\Gaming-Optimizer.ps1 -Mode EnableAll
  .\Gaming-Optimizer.ps1 -Mode DisableAll -KeepApps Zoom,Discord -KeepServices Spooler,WSearch

No changes are made until the checklist is confirmed with YES. KeepApps uses app
IDs from Get-AppCatalog or package Names from the audit. KeepServices uses exact
reviewed service names. Other services are already preserved.

Advanced Apply/Session/Restore commands remain for individual operations. The
menu is the normal entry point. The launcher uses a process-local execution-policy
override and does not change the machine's PowerShell execution policy.

VALIDATION

  Invoke-Pester -Script .\Tests.ps1,.\ServicesSecurity.Tests.ps1

Registry tests use an isolated temporary key. Service/security tests mock their
backends and do not disable real services, security or apps. Automated checks
cannot establish FPS gains, every vendor's overlay state or loader compatibility.
After applying/restarting, check audio, networking and all input devices.
