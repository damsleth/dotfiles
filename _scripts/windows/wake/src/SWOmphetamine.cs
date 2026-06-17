using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class SWOmphetamine {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint SetThreadExecutionState(uint esFlags);

    const uint ES_CONTINUOUS       = 0x80000000;
    const uint ES_DISPLAY_REQUIRED = 0x00000002;
    const uint ES_SYSTEM_REQUIRED  = 0x00000001;

    [STAThread]
    static void Main() {
        SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        NotifyIcon tray = new NotifyIcon();
        tray.Icon    = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        tray.Text    = "SWOmphetamine — session awake";
        tray.Visible = true;

        ContextMenuStrip menu = new ContextMenuStrip();
        menu.Items.Add("Exit", null, delegate(object s, EventArgs e) {
            Application.Exit();
        });
        tray.ContextMenuStrip = menu;

        Application.ApplicationExit += delegate(object s, EventArgs e) {
            SetThreadExecutionState(ES_CONTINUOUS); // release the lock on exit
            tray.Visible = false;
        };

        Application.Run();
    }
}
