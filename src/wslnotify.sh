# shellcheck shell=bash
title=""
body=""
title_set=0
body_set=0

help_short="wslnotify [OPTIONS] TEXT [TEXT ...]"
help_details='Send a Windows toast notification from WSL.

Arguments:
  TEXT  Notification text. All remaining command-line words are joined as
        the body of the toast.

Options:
  -t, --title TITLE  Set the first, bold line of the toast; default: WSL.
  --                 End option parsing; use before TEXT that starts with a dash.
  -h, --help         Show this help.
  -v, --version      Show the wslu version.

The toast is shown under the Windows PowerShell app identity, so it lands
in the Windows Action Center. Windows notification settings for Windows
PowerShell can suppress it entirely.

Examples:
  wslnotify "build finished"
  wslnotify --title "backup" "3 files copied"
  long-command && wslnotify done'

function send_toast {
    local appid='{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    winps_exec "\$ErrorActionPreference='Stop'; \$appid='$appid'; [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]; \$xml=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02); \$texts=\$xml.GetElementsByTagName('text'); [void]\$texts.Item(0).AppendChild(\$xml.CreateTextNode($(winps_string "$1"))); [void]\$texts.Item(1).AppendChild(\$xml.CreateTextNode($(winps_string "$2"))); [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$appid).Show([Windows.UI.Notifications.ToastNotification]::new(\$xml))"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) help "$0" "$help_short"; exit;;
        -v|--version) version; exit;;
        -t|--title)
            if [ -z "${2:-}" ] || [[ "$2" == -* ]]; then
                error_echo "$1 requires TITLE." 22
            fi
            title_set=1
            title="$2"
            shift 2;;
        --)
            shift
            if [ "$#" -gt 0 ]; then
                body_set=1
                body="$*"
            fi
            break;;
        -*) error_echo "Unexpected option: $1" 22; exit 22;;
        *) body_set=1; body="$*"; break;;
    esac
done

[ "$title_set" -eq 1 ] || title="WSL"
[ "$body_set" -eq 1 ] || error_echo "No input, aborting" 21
[ -n "$body" ] || error_echo "TEXT cannot be empty." 22
send_toast "$title" "$body"
