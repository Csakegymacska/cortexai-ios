using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace CortexAI
{
    // ── Design tokens ──────────────────────────────────────────────────────
    static class Tz
    {
        public static readonly Color Ink = Color.FromArgb(6, 6, 8);
        public static readonly Color Rail = Color.FromArgb(10, 10, 13);
        public static readonly Color Surface = Color.FromArgb(18, 18, 23);
        public static readonly Color Raised = Color.FromArgb(25, 25, 32);
        public static readonly Color Line = Color.FromArgb(36, 36, 46);
        public static readonly Color Text = Color.FromArgb(244, 244, 247);
        public static readonly Color Muted = Color.FromArgb(150, 150, 166);
        public static readonly Color Faint = Color.FromArgb(100, 100, 118);
        public static readonly Color Violet = Color.FromArgb(139, 92, 246);
        public static readonly Color VioletSoft = Color.FromArgb(186, 160, 255);
        public static readonly Color Magenta = Color.FromArgb(232, 121, 249);
        public static readonly Color Cyan = Color.FromArgb(34, 211, 238);
        public static readonly Color Danger = Color.FromArgb(251, 113, 133);
        public static readonly Color Ok = Color.FromArgb(52, 211, 153);

        public static Font F(float size, bool bold = false)
        {
            return new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Point);
        }
        public static Font Mono(float size)
        {
            try { return new Font("Consolas", size, FontStyle.Regular, GraphicsUnit.Point); }
            catch { return F(size); }
        }
        public static Color Alpha(Color c, int a) { return Color.FromArgb(a, c.R, c.G, c.B); }
    }

    // ── Drawing helpers ────────────────────────────────────────────────────
    static class Px
    {
        public static GraphicsPath Round(RectangleF r, float radius)
        {
            var path = new GraphicsPath();
            float d = Math.Max(1f, Math.Min(radius * 2f, Math.Min(r.Width, r.Height)));
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        /// <summary>Bubble with one tighter corner (the side the message belongs to).</summary>
        public static GraphicsPath Bubble(RectangleF r, float radius, float tight, bool tightRight)
        {
            var path = new GraphicsPath();
            float big = radius * 2f;
            float small = tight * 2f;
            path.AddArc(r.X, r.Y, big, big, 180, 90);
            path.AddArc(r.Right - big, r.Y, big, big, 270, 90);
            if (tightRight)
            {
                path.AddLine(r.Right, r.Bottom - big, r.Right, r.Bottom - small);
                path.AddArc(r.Right - small, r.Bottom - small, small, small, 0, 90);
            }
            else
            {
                path.AddArc(r.Right - big, r.Bottom - big, big, big, 0, 90);
            }
            if (tightRight)
            {
                path.AddArc(r.X, r.Bottom - big, big, big, 90, 90);
            }
            else
            {
                path.AddArc(r.X, r.Bottom - small, small, small, 120, 60);
                path.AddLine(r.X + small * 0.4f, r.Bottom - big, r.X, r.Bottom - big);
            }
            path.CloseFigure();
            return path;
        }

        public static void Fill(Graphics g, GraphicsPath path, Color color)
        {
            using (var b = new SolidBrush(color)) g.FillPath(b, path);
        }

        public static void Stroke(Graphics g, GraphicsPath path, Color color, float width)
        {
            using (var p = new Pen(color, width)) g.DrawPath(p, path);
        }

        public static void Glow(Graphics g, Rectangle area, Color color, int alpha, int radius)
        {
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(area);
                using (var brush = new PathGradientBrush(path))
                {
                    brush.CenterColor = Color.FromArgb(alpha, color);
                    brush.SurroundColors = new Color[] { Color.FromArgb(0, color) };
                    g.FillPath(brush, path);
                }
            }
        }

        public static string Ellipsis(string text, Font font, int width)
        {
            if (text == null) return "";
            if (TextRenderer.MeasureText(text, font).Width <= width) return text;
            for (int i = text.Length - 1; i > 0; i--)
            {
                string t = text.Substring(0, i).TrimEnd() + "…";
                if (TextRenderer.MeasureText(t, font).Width <= width) return t;
            }
            return "…";
        }

        // ── tiny vector icons (no icon font dependency) ────────────────────
        public static void IconChat(Graphics g, RectangleF r, Color c)
        {
            using (var p = new Pen(c, Math.Max(1.4f, r.Height / 12f)))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                var body = new RectangleF(r.X, r.Y + r.Height * 0.06f, r.Width, r.Height * 0.72f);
                using (var path = Px.Round(body, r.Height * 0.22f)) g.DrawPath(p, path);
                g.DrawLine(p, r.X + r.Width * 0.30f, body.Bottom, r.X + r.Width * 0.24f, r.Bottom);
                g.DrawLine(p, r.X + r.Width * 0.24f, r.Bottom, r.X + r.Width * 0.46f, body.Bottom);
            }
        }

        public static void IconImage(Graphics g, RectangleF r, Color c)
        {
            using (var p = new Pen(c, Math.Max(1.4f, r.Height / 12f)))
            {
                p.LineJoin = LineJoin.Round;
                var body = new RectangleF(r.X, r.Y, r.Width, r.Height);
                using (var path = Px.Round(body, r.Height * 0.24f)) g.DrawPath(p, path);
                using (var b = new SolidBrush(c))
                    g.FillEllipse(b, r.X + r.Width * 0.22f, r.Y + r.Height * 0.24f, r.Width * 0.17f, r.Height * 0.17f);
                g.DrawLines(p, new PointF[]
                {
                    new PointF(r.X + r.Width * 0.12f, r.Y + r.Height * 0.78f),
                    new PointF(r.X + r.Width * 0.42f, r.Y + r.Height * 0.46f),
                    new PointF(r.X + r.Width * 0.66f, r.Y + r.Height * 0.70f),
                    new PointF(r.X + r.Width * 0.82f, r.Y + r.Height * 0.56f),
                    new PointF(r.X + r.Width * 0.90f, r.Y + r.Height * 0.66f),
                });
            }
        }

        public static void IconSend(Graphics g, RectangleF r, Color c)
        {
            using (var b = new SolidBrush(c))
            {
                var pts = new PointF[]
                {
                    new PointF(r.X + r.Width * 0.10f, r.Y + r.Height * 0.50f),
                    new PointF(r.X + r.Width * 0.92f, r.Y + r.Height * 0.14f),
                    new PointF(r.X + r.Width * 0.60f, r.Y + r.Height * 0.88f),
                    new PointF(r.X + r.Width * 0.46f, r.Y + r.Height * 0.58f),
                };
                g.FillPolygon(b, pts);
            }
        }

        public static void IconStop(Graphics g, RectangleF r, Color c)
        {
            using (var path = Px.Round(new RectangleF(r.X + r.Width * 0.24f, r.Y + r.Height * 0.24f, r.Width * 0.52f, r.Height * 0.52f), r.Width * 0.10f))
            using (var b = new SolidBrush(c)) g.FillPath(b, path);
        }

        public static void IconSave(Graphics g, RectangleF r, Color c)
        {
            using (var p = new Pen(c, Math.Max(1.4f, r.Height / 12f)))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                g.DrawLine(p, r.X + r.Width * 0.5f, r.Y + r.Height * 0.12f, r.X + r.Width * 0.5f, r.Y + r.Height * 0.62f);
                g.DrawLines(p, new PointF[]
                {
                    new PointF(r.X + r.Width * 0.28f, r.Y + r.Height * 0.42f),
                    new PointF(r.X + r.Width * 0.50f, r.Y + r.Height * 0.64f),
                    new PointF(r.X + r.Width * 0.72f, r.Y + r.Height * 0.42f),
                });
                g.DrawLines(p, new PointF[]
                {
                    new PointF(r.X + r.Width * 0.14f, r.Y + r.Height * 0.74f),
                    new PointF(r.X + r.Width * 0.14f, r.Y + r.Height * 0.90f),
                    new PointF(r.X + r.Width * 0.86f, r.Y + r.Height * 0.90f),
                    new PointF(r.X + r.Width * 0.86f, r.Y + r.Height * 0.74f),
                });
            }
        }

        public static void IconSparkle(Graphics g, RectangleF r, Color c)
        {
            using (var b = new SolidBrush(c))
            {
                float cx = r.X + r.Width / 2f, cy = r.Y + r.Height / 2f;
                float R = r.Width * 0.46f, r2 = R * 0.26f;
                var pts = new List<PointF>();
                for (int i = 0; i < 8; i++)
                {
                    double a = Math.PI / 4 * i - Math.PI / 2;
                    float rad = (i % 2 == 0) ? R : r2;
                    pts.Add(new PointF(cx + (float)Math.Cos(a) * rad, cy + (float)Math.Sin(a) * rad));
                }
                g.FillPolygon(b, pts.ToArray());
            }
        }

        public static void Orb(Graphics g, RectangleF r, float thickness)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(r);
                using (var brush = new PathGradientBrush(path))
                {
                    brush.CenterPoint = new PointF(r.X + r.Width * 0.5f, r.Y + r.Height * 0.42f);
                    brush.CenterColor = Color.FromArgb(90, Tz.Cyan);
                    brush.SurroundColors = new Color[] { Color.FromArgb(240, Tz.Violet) };
                    using (var pen = new Pen(brush, thickness)) g.DrawEllipse(pen, r);
                }
            }
            using (var b = new SolidBrush(Color.FromArgb(8, 8, 12)))
                g.FillEllipse(b, new RectangleF(r.X + r.Width * 0.30f, r.Y + r.Height * 0.30f, r.Width * 0.40f, r.Height * 0.40f));
        }
    }

    // ── API ────────────────────────────────────────────────────────────────
    static class Api
    {
        const string BaseUrl = "https://cortanime.eu/api/cortexai";
        static readonly string ClientId = Guid.NewGuid().ToString();
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

        static Api() { try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { } }

        static string Send(string method, string path, string body)
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(BaseUrl + path);
                req.Method = method;
                req.ContentType = "application/json; charset=utf-8";
                req.UserAgent = "CortexAI-Windows/2.1";
                req.Headers.Add("X-Cortex-Client", ClientId);
                req.Timeout = 180000;
                req.ReadWriteTimeout = 180000;
                req.KeepAlive = false;
                if (body != null)
                {
                    byte[] bytes = Encoding.UTF8.GetBytes(body);
                    req.ContentLength = bytes.Length;
                    using (Stream s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
                }
                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var rs = resp.GetResponseStream())
                using (var reader = new StreamReader(rs, Encoding.UTF8))
                    return reader.ReadToEnd();
            }
            catch (WebException ex)
            {
                string detail = "";
                try
                {
                    if (ex.Response != null)
                        using (var rs = ex.Response.GetResponseStream())
                        using (var reader = new StreamReader(rs, Encoding.UTF8))
                            detail = reader.ReadToEnd();
                }
                catch { }
                throw new Exception(Friendly(detail, ex.Message));
            }
        }

        static string Friendly(string detail, string fallback)
        {
            if (string.IsNullOrEmpty(detail)) return fallback;
            try
            {
                var dict = Json.Deserialize<Dictionary<string, object>>(detail);
                if (dict.ContainsKey("message") && dict["message"] != null) return dict["message"].ToString();
                if (dict.ContainsKey("error") && dict["error"] != null) return dict["error"].ToString();
            }
            catch { }
            return detail.Length > 220 ? detail.Substring(0, 220) : detail;
        }

        public static string Serialize(object value) { return Json.Serialize(value); }

        public static T Deserialize<T>(string value) { return Json.Deserialize<T>(value); }

        public static string Chat(List<Dictionary<string, string>> history, List<string> memory)
        {
            var body = new Dictionary<string, object>();
            body["messages"] = history;
            if (memory != null && memory.Count > 0) body["memory"] = memory;
            body["tier"] = "phantom";
            body["stream"] = false;
            var dict = Json.Deserialize<Dictionary<string, object>>(Send("POST", "/chat", Json.Serialize(body)));
            if (dict.ContainsKey("text") && dict["text"] != null) return dict["text"].ToString();
            if (dict.ContainsKey("message") && dict["message"] != null) return dict["message"].ToString();
            return "(üres válasz)";
        }

        public static string CreateImage(string prompt, string style)
        {
            var body = new Dictionary<string, object>();
            body["prompt"] = prompt;
            body["style"] = style;
            var dict = Json.Deserialize<Dictionary<string, object>>(Send("POST", "/image", Json.Serialize(body)));
            object ok;
            dict.TryGetValue("ok", out ok);
            if (ok is bool && (bool)ok && dict.ContainsKey("id") && dict["id"] != null) return dict["id"].ToString();
            throw new Exception(dict.ContainsKey("message") && dict["message"] != null
                ? dict["message"].ToString() : "A képstúdió most nem érhető el.");
        }

        public static string ImageStatus(string id, out string status)
        {
            var dict = Json.Deserialize<Dictionary<string, object>>(Send("GET", "/image/" + Uri.EscapeDataString(id), null));
            status = dict.ContainsKey("status") && dict["status"] != null ? dict["status"].ToString() : "unknown";
            return dict.ContainsKey("url") && dict["url"] != null ? dict["url"].ToString() : null;
        }

        public static byte[] Download(string url)
        {
            using (var wc = new WebClient())
            {
                wc.Headers.Add("User-Agent", "CortexAI-Windows/2.1");
                return wc.DownloadData(url);
            }
        }
    }

    // ── Message model ──────────────────────────────────────────────────────
    sealed class Msg
    {
        public bool Me;
        public string Text;
        public DateTime At = DateTime.Now;
        public bool Pending;
        public List<Part> Parts = new List<Part>();
        public float Height;
        public float LastWidth = -1;
        public string MeasuredText;

        public sealed class Part
        {
            public bool Code;
            public string Text;
            public List<string> Lines = new List<string>();
            public float H;
        }
    }

    // ── The window ─────────────────────────────────────────────────────────
    sealed class Shell : Form
    {
        const int SidebarWidth = 250;
        const int TitleHeight = 0;

        readonly Timer tick = new Timer();
        readonly List<Msg> messages = new List<Msg>();
        readonly List<Dictionary<string, string>> history = new List<Dictionary<string, string>>();
        readonly List<string> memory = new List<string>();

        // pages: 0 = chat, 1 = images
        int page = 0;
        int hover = -1;
        int hoverPage = -1;

        float scrollChat = 0f;
        bool stickToBottom = true;
        float contentH = 0f;

        TextBox chatInput;
        Panel chatHost;
        Label chatPh;
        Label promptPh;
        TextBox promptInput;
        Panel promptHost;
        Button hiddenSave;

        bool busyChat;
        bool busyImage;
        string statusLine = "";
        Color statusColor = Tz.Faint;

        // image page state
        int styleIndex = 0;
        readonly string[] styleIds = { "auto", "anime", "cinema", "icon", "render", "sketch" };
        readonly string[] styleNames = { "Auto", "Anime", "Mozi", "Ikon", "3D", "Vázlat" };
        Image rendered;
        byte[] renderedBytes;
        readonly List<Image> thumbs = new List<Image>();
        float animPhase;
        readonly List<KeyValuePair<Rectangle, string>> chips = new List<KeyValuePair<Rectangle, string>>();

        // window buttons rects
        Rectangle rMin, rMax, rClose;

        public Shell(string startPage = "chat")
        {
            Text = "Cortex AI";
            Icon = LoadIco();
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(1000, 660);
            ClientSize = new Size(1200, 800);
            BackColor = Tz.Ink;
            Font = Tz.F(9.75f);
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            KeyPreview = true;

            BuildComposer();
            BuildPrompt();

            LoadStore();
            if (messages.Count == 0)
            {
                messages.Add(new Msg
                {
                    Me = false,
                    Text = "Szia! Cortex Phantom vagyok, az OmegaTech és a CortexAnime AI-ja.\n\nKérdezz bármit — vagy válts a bal oldalon a Képek fülre, és írd le, mit rajzoljak."
                });
            }
            FormClosing += (s, e) => SaveStore();

            tick.Interval = 60;
            tick.Tick += (s, e) => { animPhase += 0.06f; if (busyChat || busyImage) Invalidate(); };
            tick.Start();

            if (startPage == "images") { page = 1; }
            MouseWheel += (s, e) => ScrollChat(e.Delta);
            Resize += (s, e) => LayoutChildren();
            Load += (s, e) => { LayoutChildren(); ShowPages(); TryDarkFrame(); };
        }

        static Icon LoadIco()
        {
            try
            {
                var stream = typeof(Shell).Assembly.GetManifestResourceStream("CortexAI.cortex.ico");
                if (stream != null) return new Icon(stream);
            }
            catch { }
            return null;
        }

        // ── native look (best effort, silently ignored elsewhere) ──────────
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        void TryDarkFrame()
        {
            try
            {
                int on = 1;
                DwmSetWindowAttribute(Handle, 20, ref on, sizeof(int));   // dark title area
                int round = 2;
                DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int)); // rounded corners (Win11)
            }
            catch { }
        }

        [DllImport("user32.dll")]
        static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        protected override void WndProc(ref Message m)
        {
            const int WM_NCHITTEST = 0x84;
            if (m.Msg == WM_NCHITTEST)
            {
                var p = PointToClient(new Point(m.LParam.ToInt32() & 0xFFFF, (m.LParam.ToInt32() >> 16) & 0xFFFF));
                const int grip = 7;
                bool left = p.X <= grip, right = p.X >= ClientSize.Width - grip;
                bool top = p.Y <= grip, bottom = p.Y >= ClientSize.Height - grip;
                if (top && left) { m.Result = (IntPtr)13; return; }
                if (top && right) { m.Result = (IntPtr)14; return; }
                if (bottom && left) { m.Result = (IntPtr)16; return; }
                if (bottom && right) { m.Result = (IntPtr)17; return; }
                if (left) { m.Result = (IntPtr)10; return; }
                if (right) { m.Result = (IntPtr)11; return; }
                if (top) { m.Result = (IntPtr)12; return; }
                if (bottom) { m.Result = (IntPtr)15; return; }
            }
            base.WndProc(ref m);
        }

        void DragWindow()
        {
            try { ReleaseCapture(); SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); }
            catch { }
        }

        // ── child controls ─────────────────────────────────────────────────
        void BuildComposer()
        {
            chatHost = new Panel { BackColor = Tz.Raised, Visible = true };
            chatInput = new TextBox
            {
                Multiline = true,
                BorderStyle = BorderStyle.None,
                BackColor = Tz.Raised,
                ForeColor = Tz.Text,
                Font = Tz.F(10.5f),
                ScrollBars = ScrollBars.None,
                AcceptsReturn = false
            };
            chatInput.KeyDown += async (s, e) =>
            {
                if (e.KeyCode == Keys.Enter && !e.Shift) { e.SuppressKeyPress = true; await SendChat(); }
            };
            chatInput.TextChanged += (s, e) => { if (chatPh != null) chatPh.Visible = chatInput.TextLength == 0 && page == 0; Invalidate(); };
            chatHost.Controls.Add(chatInput);
            Controls.Add(chatHost);
            Controls.Add(ChatSendButton());

            chatPh = new Label
            {
                Text = "Írj a Cortex Voidnak…    Enter küld, Shift+Enter új sor",
                ForeColor = Color.FromArgb(120, 122, 126, 146),
                BackColor = Tz.Raised,
                Font = Tz.F(10f),
                AutoSize = false,
                TextAlign = ContentAlignment.MiddleLeft,
                Cursor = Cursors.IBeam
            };
            chatPh.Click += (s, e) => chatInput.Focus();
            Controls.Add(chatPh);
            chatPh.BringToFront();
        }

        Control chatSend;
        Control ChatSendButton()
        {
            var b = new Panel { BackColor = Color.Transparent, Cursor = Cursors.Hand };
            b.Paint += (s, e) => PaintSendButton(e.Graphics, b.ClientRectangle);
            b.Click += async (s, e) => await SendChat();
            chatSend = b;
            return b;
        }

        void BuildPrompt()
        {
            promptHost = new Panel { BackColor = Tz.Raised, Visible = false };
            promptInput = new TextBox
            {
                BorderStyle = BorderStyle.None,
                BackColor = Tz.Raised,
                ForeColor = Tz.Text,
                Font = Tz.F(10.5f),
                Text = "Fekete háttéren lila fénygyűrű, középen izzó gömb"
            };
            promptHost.Controls.Add(promptInput);
            Controls.Add(promptHost);
            promptInput.HideSelection = true;
            promptInput.SelectionStart = promptInput.TextLength;

            promptPh = new Label
            {
                Text = "Írd le a képet, amit szeretnél…",
                ForeColor = Color.FromArgb(120, 122, 126, 146),
                BackColor = Tz.Raised,
                Font = Tz.F(10f),
                AutoSize = false,
                TextAlign = ContentAlignment.MiddleLeft,
                Cursor = Cursors.IBeam,
                Visible = false
            };
            promptPh.Click += (s, e) => promptInput.Focus();
            promptInput.TextChanged += (s, e) => { promptPh.Visible = page == 1 && promptInput.TextLength == 0; };
            Controls.Add(promptPh);
            promptPh.BringToFront();

            hiddenSave = new Button { Visible = false };
            hiddenSave.Click += (s, e) => SaveRendered();
            Controls.Add(hiddenSave);
        }

        void LayoutChildren()
        {
            int mainX = SidebarWidth;
            int w = ClientSize.Width - mainX;

            // composer
            int cw = w - 64;
            int ch = 78;
            int cx = mainX + 32;
            int cy = ClientSize.Height - ch - 24;
            chatHost.Bounds = new Rectangle(cx + 18, cy + 20, cw - 120, 40);
            chatInput.Bounds = new Rectangle(0, 0, chatHost.Width, chatHost.Height);
            if (chatPh != null) chatPh.Bounds = new Rectangle(cx + 20, cy + 22, cw - 130, 34);
            ((Control)chatSend).Bounds = new Rectangle(cx + cw - 66, cy + 18, 44, 44);

            promptHost.Bounds = new Rectangle(mainX + 80, 118, w - 168, 28);
            promptInput.Bounds = new Rectangle(0, 3, promptHost.Width, 22);
            if (promptPh != null) promptPh.Bounds = new Rectangle(mainX + 80, 117, w - 168, 30);

            rClose = new Rectangle(ClientSize.Width - 46, 14, 32, 30);
            rMax = new Rectangle(ClientSize.Width - 82, 14, 32, 30);
            rMin = new Rectangle(ClientSize.Width - 118, 14, 32, 30);
            Invalidate();
        }

        // ── navigation / mouse ─────────────────────────────────────────────
        Rectangle NavRect(int index) { return new Rectangle(18, 108 + index * 50, SidebarWidth - 36, 42); }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int h = -1;
            if (e.X < SidebarWidth)
            {
                for (int i = 0; i < 2; i++) if (NavRect(i).Contains(e.Location)) h = 100 + i;
            }
            if (rClose.Contains(e.Location)) h = 3;
            else if (rMax.Contains(e.Location)) h = 4;
            else if (rMin.Contains(e.Location)) h = 5;
            if (page == 1)
            {
                for (int i = 0; i < styleNames.Length; i++)
                    if (StyleRect(i).Contains(e.Location)) h = 200 + i;
                if (GenRect().Contains(e.Location)) h = 300;
                if (SaveRect().Contains(e.Location)) h = 301;
                for (int i = 0; i < thumbs.Count; i++)
                    if (ThumbRect(i).Contains(e.Location)) h = 400 + i;
            }
            if (h != hover) { hover = h; Cursor = (h >= 0 && h < 100) ? Cursors.Hand : ((h >= 100 && h < 200) ? Cursors.Hand : Cursors.Default); Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                if (rClose.Contains(e.Location)) { Close(); return; }
                if (rMax.Contains(e.Location)) { WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; return; }
                if (rMin.Contains(e.Location)) { WindowState = FormWindowState.Minimized; return; }
                for (int i = 0; i < 2; i++) if (NavRect(i).Contains(e.Location)) { page = i; ShowPages(); return; }
                if (page == 0)
                {
                    foreach (var chip in chips)
                    {
                        if (chip.Key.Contains(e.Location))
                        {
                            chatInput.Text = chip.Value;
                            var fire = SendChat();
                            return;
                        }
                    }
                }
                if (page == 1)
                {
                    for (int i = 0; i < styleNames.Length; i++) if (StyleRect(i).Contains(e.Location)) { styleIndex = i; Invalidate(); return; }
                    if (GenRect().Contains(e.Location) && !busyImage) { var t = Generate(); return; }
                    if (SaveRect().Contains(e.Location)) { SaveRendered(); return; }
                }
            }
            base.OnMouseClick(e);
        }

        void ShowPages()
        {
            chatHost.Visible = page == 0;
            ((Control)chatSend).Visible = page == 0;
            promptHost.Visible = page == 1;
            if (chatPh != null) chatPh.Visible = page == 0 && chatInput.TextLength == 0;
            if (promptPh != null) promptPh.Visible = page == 1 && promptInput.TextLength == 0;
            Invalidate();
        }

        void ScrollChat(int delta)
        {
            if (page != 0) return;
            float viewH = TranscriptBottom - TranscriptTop;
            float max = Math.Max(0, contentH - viewH + 8);
            scrollChat -= delta * 0.9f;
            if (scrollChat < 0) scrollChat = 0;
            if (scrollChat > max) scrollChat = max;
            stickToBottom = Math.Abs(scrollChat - max) < 2f;
            Invalidate();
        }

        // ── painting ───────────────────────────────────────────────────────
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Tz.Ink);

            int w = ClientSize.Width, h = ClientSize.Height;
            Px.Glow(g, new Rectangle(-260, -300, 900, 760), Tz.Violet, 26, 0);
            Px.Glow(g, new Rectangle(w - 640, h - 560, 900, 720), Tz.Cyan, 16, 0);

            PaintSidebar(g, h);
            PaintHeader(g, w);

            if (page == 0) PaintChat(g, w, h);
            else PaintImages(g, w, h);

            using (var pen = new Pen(Color.FromArgb(255, 40, 40, 52)))
                g.DrawRectangle(pen, 0, 0, w - 1, h - 1);

            PaintWindowButtons(g);
        }

        void PaintSidebar(Graphics g, int h)
        {
            using (var b = new SolidBrush(Color.FromArgb(235, 10, 10, 13)))
                g.FillRectangle(b, 0, 0, SidebarWidth, h);
            using (var p = new Pen(Tz.Line))
                g.DrawLine(p, SidebarWidth, 0, SidebarWidth, h);

            Px.Orb(g, new RectangleF(22, 22, 34, 34), 2.2f);
            TextRenderer.DrawText(g, "Cortex AI", Tz.F(13.5f, true), new Rectangle(68, 22, 170, 22), Tz.Text, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, "Cortex Void", Tz.F(8.5f), new Rectangle(69, 43, 170, 16), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);

            TextRenderer.DrawText(g, "MUNKA", Tz.F(7.25f, true), new Rectangle(24, 90, 120, 14), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);

            string[] labels = { "Chat", "Képek" };
            for (int i = 0; i < 2; i++)
            {
                var r = NavRect(i);
                bool active = page == i;
                bool hov = hover == 100 + i;
                if (active || hov)
                {
                    using (var path = Px.Round(r, 12))
                    {
                        Px.Fill(g, path, active ? Tz.Raised : Color.FromArgb(14, 20, 20, 26));
                        if (active) Px.Stroke(g, path, Color.FromArgb(20, 255, 255, 255), 1);
                    }
                    if (active)
                    {
                        using (var accent = Px.Round(new RectangleF(r.X + 6, r.Y + 11, 3, r.Height - 22), 1.5f))
                            using (var b = new LinearGradientBrush(new Rectangle(r.X + 6, r.Y + 11, 3, r.Height - 22), Tz.Cyan, Tz.Magenta, 90f))
                                g.FillPath(b, accent);
                    }
                }
                var iconRect = new RectangleF(r.X + 18, r.Y + 12, 18, 18);
                var color = active ? Tz.Text : (hov ? Tz.Muted : Tz.Muted);
                if (i == 0) Px.IconChat(g, iconRect, active ? Tz.VioletSoft : color);
                else Px.IconImage(g, iconRect, active ? Tz.VioletSoft : color);
                TextRenderer.DrawText(g, labels[i], Tz.F(10.25f, active), new Rectangle(r.X + 48, r.Y + 12, 150, 20), active ? Tz.Text : color, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            }

            // model card at the bottom
            var card = new Rectangle(18, h - 104, SidebarWidth - 36, 76);
            using (var path = Px.Round(card, 14))
            {
                Px.Fill(g, path, Color.FromArgb(140, 18, 18, 23));
                Px.Stroke(g, path, Color.FromArgb(16, 255, 255, 255), 1);
            }
            Px.Orb(g, new RectangleF(card.X + 14, card.Y + 20, 34, 34), 2f);
            TextRenderer.DrawText(g, "Cortex Void", Tz.F(9.75f, true), new Rectangle(card.X + 58, card.Y + 19, 165, 18), Tz.Text, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, "OmegaTech × CortexAnime", Tz.F(7.5f), new Rectangle(card.X + 58, card.Y + 37, 180, 14), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, "v2.0.0", Tz.F(7.25f), new Rectangle(card.X + 58, card.Y + 51, 80, 14), Color.FromArgb(76, 100, 100, 118), TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
        }

        void PaintHeader(Graphics g, int w)
        {
            string title = page == 0 ? "Chat" : "Képek";
            string sub = page == 0
                ? (busyChat ? "A Cortex Void ír…" : "Cortex Void · azonnali válasz")
                : (busyImage ? "Festés folyamatban…" : "Cortex Void Canvas · ingyenes kép");

            TextRenderer.DrawText(g, title, Tz.F(14.5f, true), new Rectangle(SidebarWidth + 32, 17, 400, 26), Tz.Text, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, sub, Tz.F(8.75f), new Rectangle(SidebarWidth + 32, 41, 460, 18), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            using (var p = new Pen(Color.FromArgb(90, 36, 36, 46)))
                g.DrawLine(p, SidebarWidth, 66, w, 66);
        }

        void PaintWindowButtons(Graphics g)
        {
            PaintWinButton(g, rMin, hover == 5, "min");
            PaintWinButton(g, rMax, hover == 4, "max");
            PaintWinButton(g, rClose, hover == 3, "close");
        }

        void PaintWinButton(Graphics g, Rectangle r, bool hov, string kind)
        {
            if (hov)
            {
                using (var path = Px.Round(r, 8))
                    Px.Fill(g, path, kind == "close" ? Color.FromArgb(200, 190, 40, 60) : Color.FromArgb(26, 30, 30, 40));
            }
            var c = hov && kind == "close" ? Color.White : Tz.Muted;
            using (var p = new Pen(c, 1.4f))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
                float cx = r.X + r.Width / 2f, cy = r.Y + r.Height / 2f;
                if (kind == "min") g.DrawLine(p, cx - 5, cy + 3, cx + 5, cy + 3);
                else if (kind == "max") g.DrawLines(p, new PointF[] {
                    new PointF(cx - 5, cy - 4), new PointF(cx + 5, cy - 4),
                    new PointF(cx + 5, cy + 5), new PointF(cx - 5, cy + 5), new PointF(cx - 5, cy - 4) });
                else g.DrawLine(p, cx - 5, cy - 5, cx + 5, cy + 5);
                if (kind == "close") g.DrawLine(p, cx + 5, cy - 5, cx - 5, cy + 5);
            }
        }

        // ── chat painting ──────────────────────────────────────────────────
        int ContentLeft { get { return SidebarWidth + 32; } }
        int ContentRight { get { return ClientSize.Width - 32; } }
        int TranscriptTop { get { return 88; } }
        int TranscriptBottom { get { return ClientSize.Height - 78 - 24 - 16; } }

        Font bodyFont, codeFont, timeFont;
        Font BodyFont { get { return bodyFont ?? (bodyFont = Tz.F(10.5f)); } }
        Font CodeFont { get { return codeFont ?? (codeFont = Tz.Mono(9.5f)); } }
        Font TimeFont { get { return timeFont ?? (timeFont = Tz.F(7.75f)); } }

        void PaintChat(Graphics g, int w, int h)
        {
            var clip = new Rectangle(ContentLeft - 8, TranscriptTop, ContentRight - ContentLeft + 16, TranscriptBottom - TranscriptTop);
            var state = g.Save();
            g.SetClip(clip);

            int bubbleMax = Math.Min(720, (int)((ContentRight - ContentLeft) * 0.78f));
            float y = TranscriptTop + 8 - scrollChat;
            float startY = y;

            foreach (var m in messages)
            {
                float used = LayoutMessage(g, m, bubbleMax);
                float x = m.Me ? ContentRight - used : ContentLeft + (m.Me ? 0 : 38);
                PaintMessage(g, m, x, y, used);
                y += m.Height + 18;
            }
            contentH = (y + scrollChat) - (TranscriptTop + 8);
            if (stickToBottom)
            {
                float viewH = TranscriptBottom - TranscriptTop;
                float target = Math.Max(0, contentH - viewH + 8);
                if (Math.Abs(target - scrollChat) > 0.5f) { scrollChat = target; Invalidate(); }
            }

            chips.Clear();
            if (messages.Count == 1 && !busyChat)
                PaintSuggestions(g, ref y);

            g.Restore(state);

            // fade only while the transcript is actually scrolled, so the first bubble is never clipped
            if (scrollChat > 4)
                using (var brush = new LinearGradientBrush(new Rectangle(ContentLeft - 8, TranscriptTop, ContentRight - ContentLeft + 16, 26),
                           Tz.Ink, Color.FromArgb(0, 6, 6, 8), 90f))
                    g.FillRectangle(brush, new Rectangle(ContentLeft - 8, TranscriptTop, ContentRight - ContentLeft + 16, 26));

            PaintScrollbar(g, clip);
            PaintComposer(g);
        }

        void PaintSuggestions(Graphics g, ref float y)
        {
            float cx = (ContentLeft + ContentRight) / 2f;
            float top = Math.Max(y + 26, TranscriptTop + 150);
            if (top > TranscriptBottom - 150) return;

            Px.Orb(g, new RectangleF(cx - 30, top, 60, 60), 2.6f);
            TextRenderer.DrawText(g, "Mivel kezdjük?", Tz.F(13f, true), new Rectangle((int)cx - 200, (int)top + 72, 400, 24),
                Color.FromArgb(210, 220, 220, 236), TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, "Kérdezz, kódolj, ötletelj — vagy generálj képet.", Tz.F(9f),
                new Rectangle((int)cx - 240, (int)top + 98, 480, 20), Tz.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPadding);

            string[] prompts = {
                "Mesélj egy rövid, fordulatos történetet",
                "Magyarázd el egyszerűen a fekete lyukakat",
                "Írj egy Python függvényt, ami prímeket szűr"
            };
            var font = Tz.F(9.25f);
            int gap = 10;
            int totalW = 0;
            var widths = new int[prompts.Length];
            for (int i = 0; i < prompts.Length; i++)
            {
                widths[i] = TextRenderer.MeasureText(prompts[i], font).Width + 28;
                totalW += widths[i] + (i > 0 ? gap : 0);
            }
            float startX = cx - totalW / 2f;
            float chipY = top + 132;
            for (int i = 0; i < prompts.Length; i++)
            {
                var rect = new Rectangle((int)startX, (int)chipY, widths[i], 36);
                using (var path = Px.Round(rect, 18))
                {
                    Px.Fill(g, path, Color.FromArgb(255, 20, 20, 26));
                    Px.Stroke(g, path, Color.FromArgb(26, 255, 255, 255), 1);
                }
                TextRenderer.DrawText(g, prompts[i], font, rect, Tz.Muted,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                chips.Add(new KeyValuePair<Rectangle, string>(rect, prompts[i]));
                startX += widths[i] + gap;
            }
        }

        float LayoutMessage(Graphics g, Msg m, int bubbleMax)
        {
            float width = bubbleMax;
            bool pending = m.Pending && string.IsNullOrEmpty(m.Text);
            if (pending) { m.Height = 44; return 96; }

            bool dirty = m.LastWidth != width || m.MeasuredText != m.Text || m.Parts.Count == 0;
            if (dirty)
            {
                m.LastWidth = width;
                m.MeasuredText = m.Text;
                m.Parts = SplitParts(m.Text);
                float total = 0;
                foreach (var part in m.Parts)
                {
                    if (part.Code)
                    {
                        part.Lines = new List<string>(part.Text.Replace("\r", "").Split('\n'));
                        part.H = part.Lines.Count * 17f + 20;
                    }
                    else
                    {
                        part.H = TextRenderer.MeasureText(g, part.Text, BodyFont,
                            new Size((int)width - 32, 2000), TextFormatFlags.WordBreak | TextFormatFlags.NoPadding).Height;
                    }
                    total += part.H + (part == m.Parts[0] ? 0 : 8);
                }
                m.Height = total + 26;
            }
            // width of the longest line for the bubble
            float widest = 0;
            foreach (var part in m.Parts)
            {
                if (part.Code)
                {
                    foreach (var line in part.Lines)
                        widest = Math.Max(widest, TextRenderer.MeasureText(line, CodeFont).Width);
                }
                else
                {
                    var size = TextRenderer.MeasureText(g, part.Text, BodyFont, new Size((int)width - 32, 2000),
                        TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                    widest = Math.Max(widest, size.Width);
                }
            }
            return Math.Min(bubbleMax, Math.Max(120, widest + 32));
        }

        static List<Msg.Part> SplitParts(string text)
        {
            var parts = new List<Msg.Part>();
            if (string.IsNullOrEmpty(text)) { parts.Add(new Msg.Part { Text = "" }); return parts; }
            var chunks = text.Split(new string[] { "```" }, StringSplitOptions.None);
            for (int i = 0; i < chunks.Length; i++)
            {
                string chunk = chunks[i];
                if (i % 2 == 1)
                {
                    int nl = chunk.IndexOf('\n');
                    if (nl > 0 && nl < 20) chunk = chunk.Substring(nl + 1);
                    parts.Add(new Msg.Part { Code = true, Text = chunk.TrimEnd('\n', '\r') });
                }
                else if (chunk.Length > 0)
                {
                    parts.Add(new Msg.Part { Text = chunk.Trim('\n', '\r') });
                }
            }
            if (parts.Count == 0) parts.Add(new Msg.Part { Text = text });
            return parts;
        }

        void PaintMessage(Graphics g, Msg m, float x, float y, float width)
        {
            bool pending = m.Pending && string.IsNullOrEmpty(m.Text);

            if (!m.Me)
            {
                Px.Orb(g, new RectangleF(ContentLeft, y + 2, 26, 26), 1.8f);
            }

            var bubble = new RectangleF(x, y, width, pending ? 46 : m.Height);
            using (var path = Px.Bubble(bubble, 16, 6, m.Me))
            {
                if (m.Me)
                {
                    using (var b = new LinearGradientBrush(new Rectangle((int)bubble.X, (int)bubble.Y, (int)bubble.Width, (int)bubble.Height + 2),
                               Color.FromArgb(124, 77, 255), Color.FromArgb(104, 52, 255), 90f))
                        g.FillPath(b, path);
                }
                else
                {
                    Px.Fill(g, path, Color.FromArgb(255, 18, 18, 23));
                    Px.Stroke(g, path, Color.FromArgb(16, 255, 255, 255), 1);
                }
            }

            if (pending)
            {
                PaintDots(g, x + 18, y + 16);
            }
            else
            {
                float cy = y + 13;
                bool first = true;
                foreach (var part in m.Parts)
                {
                    if (!first) cy += 8;
                    first = false;
                    if (part.Code)
                    {
                        var box = new RectangleF(x + 12, cy, width - 24, part.H);
                        using (var path = Px.Round(box, 10))
                        {
                            Px.Fill(g, path, Color.FromArgb(255, 11, 11, 15));
                            Px.Stroke(g, path, Color.FromArgb(22, 255, 255, 255), 1);
                        }
                        float ly = box.Y + 10;
                        foreach (var line in part.Lines)
                        {
                            TextRenderer.DrawText(g, line, CodeFont, new Rectangle((int)box.X + 12, (int)ly, (int)box.Width - 24, 18),
                                Color.FromArgb(214, 214, 226), TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
                            ly += 17f;
                        }
                    }
                    else
                    {
                        var rect = new Rectangle((int)(x + 16), (int)cy, (int)width - 32, (int)part.H + 2);
                        TextRenderer.DrawText(g, part.Text, BodyFont, rect,
                            m.Me ? Color.White : Color.FromArgb(232, 232, 240),
                            TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.Left);
                    }
                    cy += part.H;
                }
            }

            if (!pending)
            {
                string stamp = m.At.ToString("HH:mm");
                var size = TextRenderer.MeasureText(stamp, TimeFont);
                float sx = m.Me ? x + width - size.Width : x;
                TextRenderer.DrawText(g, stamp, TimeFont, new Rectangle((int)sx + 2, (int)(y + m.Height + 7), 60, 14), Color.FromArgb(70, 100, 100, 118), TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            }
        }

        void PaintDots(Graphics g, float x, float y)
        {
            for (int i = 0; i < 3; i++)
            {
                float ph = animPhase + i * 0.35f;
                float a = 0.35f + 0.65f * (float)Math.Max(0, Math.Sin(ph * 2.2));
                using (var b = new SolidBrush(Color.FromArgb((int)(a * 220), 186, 160, 255)))
                    g.FillEllipse(b, x + i * 11, y + (float)Math.Sin(ph * 2.2) * 2f, 7, 7);
            }
        }

        void PaintScrollbar(Graphics g, Rectangle clip)
        {
            float viewH = clip.Height;
            if (contentH <= viewH) return;
            float trackH = viewH - 8;
            float thumbH = Math.Max(40, trackH * (viewH / contentH));
            float max = contentH - viewH;
            float t = max <= 0 ? 0 : scrollChat / max;
            float y = clip.Y + 4 + (trackH - thumbH) * t;
            var bar = new RectangleF(ClientSize.Width - 9, y, 4, thumbH);
            using (var path = Px.Round(bar, 2))
                Px.Fill(g, path, Color.FromArgb(60, 255, 255, 255));
        }

        void PaintSendButton(Graphics g, Rectangle r)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            bool can = !busyChat && !string.IsNullOrEmpty(chatInput.Text.Trim());
            var rect = new RectangleF(3, 3, r.Width - 6, r.Height - 6);
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(rect);
                if (can)
                {
                    using (var b = new LinearGradientBrush(Rectangle.Round(rect), Tz.Violet, Tz.Magenta, 45f))
                        g.FillPath(b, path);
                }
                else
                {
                    Px.Fill(g, path, Tz.Raised);
                    using (var p = new Pen(Color.FromArgb(28, 255, 255, 255))) g.DrawPath(p, path);
                }
            }
            if (busyChat) Px.IconStop(g, new RectangleF(rect.X + 12, rect.Y + 12, 20, 20), Color.White);
            else Px.IconSend(g, new RectangleF(rect.X + 11, rect.Y + 11, 22, 22), can ? Color.White : Tz.Faint);
        }

        void PaintComposer(Graphics g)
        {
            int mainX = SidebarWidth;
            int w = ClientSize.Width - mainX;
            var box = new Rectangle(mainX + 32, ClientSize.Height - 78 - 24, w - 64, 78);
            using (var path = Px.Round(box, 22))
            {
                Px.Fill(g, path, Tz.Raised);
                Px.Stroke(g, path, Color.FromArgb(26, 255, 255, 255), 1);
            }
            if (busyChat)
                TextRenderer.DrawText(g, "A Cortex Void gondolkodik…", Tz.F(8.5f), new Rectangle(box.X + 22, box.Y + 52, 300, 16), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
        }

        // ── image page ─────────────────────────────────────────────────────
        Rectangle StyleRect(int i)
        {
            int x = SidebarWidth + 32;
            int y = 176;
            int[] widths = { 74, 84, 80, 76, 62, 84 };
            for (int k = 0; k < i; k++) x += widths[k] + 8;
            return new Rectangle(x, y, widths[i], 32);
        }

        Rectangle GenRect()
        {
            int w = ClientSize.Width - SidebarWidth;
            return new Rectangle(SidebarWidth + w - 32 - 168, 170, 168, 42);
        }

        Rectangle SaveRect()
        {
            int y = ClientSize.Height - 74;
            return new Rectangle(SidebarWidth + 32, y, 168, 42);
        }

        Rectangle StageRect()
        {
            int x = SidebarWidth + 32;
            int top = 224;
            int bottom = ClientSize.Height - 96;
            return new Rectangle(x, top, ClientSize.Width - SidebarWidth - 64, Math.Max(120, bottom - top));
        }

        Rectangle ThumbRect(int i)
        {
            var s = StageRect();
            return new Rectangle(s.Right - 16 - (i + 1) * 60, s.Y + 16, 52, 52);
        }

        void PaintImages(Graphics g, int w, int h)
        {
            // prompt card
            var card = new Rectangle(SidebarWidth + 32, 92, ClientSize.Width - SidebarWidth - 64, 66);
            using (var path = Px.Round(card, 16))
            {
                Px.Fill(g, path, Tz.Raised);
                Px.Stroke(g, path, Color.FromArgb(26, 255, 255, 255), 1);
            }
            Px.IconSparkle(g, new RectangleF(card.X + 18, card.Y + 23, 18, 18), Tz.VioletSoft);
            TextRenderer.DrawText(g, "PROMPT", Tz.F(7.25f, true), new Rectangle(card.X + 50, card.Y + 8, 200, 12), Tz.Faint, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);

            for (int i = 0; i < styleNames.Length; i++)
            {
                var r = StyleRect(i);
                bool on = styleIndex == i;
                using (var path = Px.Round(r, 16))
                {
                    if (on)
                    {
                        using (var b = new LinearGradientBrush(r, Tz.Violet, Tz.Magenta, 20f)) g.FillPath(b, path);
                    }
                    else
                    {
                        Px.Fill(g, path, Tz.Surface);
                        Px.Stroke(g, path, Color.FromArgb(26, 255, 255, 255), 1);
                    }
                }
                TextRenderer.DrawText(g, styleNames[i], Tz.F(9.25f, on), r, on ? Color.White : Tz.Muted,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }

            var gen = GenRect();
            using (var path = Px.Round(gen, 21))
                using (var b = new LinearGradientBrush(gen, Tz.Violet, Tz.Magenta, 20f))
                    g.FillPath(b, path);
            Px.IconSparkle(g, new RectangleF(gen.X + 20, gen.Y + 13, 16, 16), Color.White);
            TextRenderer.DrawText(g, busyImage ? "Festés…" : "Generálás", Tz.F(10f, true),
                new Rectangle(gen.X + 44, gen.Y + 13, 110, 18), Color.White, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);

            // stage
            var stage = StageRect();
            using (var path = Px.Round(stage, 20))
            {
                Px.Fill(g, path, Color.FromArgb(255, 12, 12, 16));
                Px.Stroke(g, path, Color.FromArgb(22, 255, 255, 255), 1);
            }

            if (rendered != null)
            {
                float maxW = stage.Width - 32, maxH = stage.Height - 32;
                float scale = Math.Min(maxW / rendered.Width, maxH / rendered.Height);
                float dw = rendered.Width * scale, dh = rendered.Height * scale;
                var dest = new RectangleF(stage.X + (stage.Width - dw) / 2f, stage.Y + (stage.Height - dh) / 2f, dw, dh);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(rendered, dest);
            }
            else if (busyImage)
            {
                float cx = stage.X + stage.Width / 2f, cy = stage.Y + stage.Height / 2f;
                float angle = animPhase * 60f;
                using (var p = new Pen(Tz.Violet, 2.4f))
                {
                    p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
                    g.DrawArc(p, cx - 22, cy - 46, 44, 44, angle, 110f);
                }
                TextRenderer.DrawText(g, statusLine, Tz.F(10f), new Rectangle((int)cx - 150, (int)cy + 10, 300, 20), Tz.Muted,
                    TextFormatFlags.HorizontalCenter);
            }
            else
            {
                TextRenderer.DrawText(g, "Írd le a promptot, és nyomd meg a Generálást.", Tz.F(10f),
                    new Rectangle(stage.X, stage.Y + stage.Height / 2 - 10, stage.Width, 22), Tz.Faint,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.NoPadding);
            }

            // thumbs
            for (int i = 0; i < thumbs.Count && i < 5; i++)
            {
                var tr = ThumbRect(i);
                using (var path = Px.Round(tr, 10))
                {
                    g.SetClip(path);
                    g.DrawImage(thumbs[i], tr);
                    g.ResetClip();
                    Px.Stroke(g, path, Color.FromArgb(30, 255, 255, 255), 1);
                }
            }

            // bottom bar
            var save = SaveRect();
            bool canSave = renderedBytes != null;
            using (var path = Px.Round(save, 21))
            {
                Px.Fill(g, path, canSave ? Tz.Raised : Color.FromArgb(14, 18, 18, 23));
                Px.Stroke(g, path, Color.FromArgb(26, 255, 255, 255), 1);
            }
            Px.IconSave(g, new RectangleF(save.X + 20, save.Y + 12, 18, 18), canSave ? Tz.Text : Tz.Faint);
            TextRenderer.DrawText(g, "Kép mentése", Tz.F(9.5f, true), new Rectangle(save.X + 46, save.Y + 13, 120, 18),
                canSave ? Tz.Text : Tz.Faint, TextFormatFlags.NoPadding);

            if (!string.IsNullOrEmpty(statusLine))
                TextRenderer.DrawText(g, statusLine, Tz.F(9f), new Rectangle(save.Right + 16, save.Y + 13, 420, 18), statusColor, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPadding);
        }

        // ── behaviour ──────────────────────────────────────────────────────
        async Task SendChat()
        {
            string text = chatInput.Text.Trim();
            if (text.Length == 0 || busyChat) return;
            chatInput.Clear();

            messages.Add(new Msg { Me = true, Text = text });
            history.Add(new Dictionary<string, string> { { "role", "user" }, { "content", text } });
            if (history.Count > 30) history.RemoveRange(0, history.Count - 30);
            TryRemember(text);
            SaveStore();

            var pending = new Msg { Me = false, Pending = true };
            messages.Add(pending);
            busyChat = true;
            stickToBottom = true;
            Invalidate();

            try
            {
                var snapshot = new List<Dictionary<string, string>>(history);
                var carried = new List<string>(memory);
                string reply = await Task.Run(() => Api.Chat(snapshot, carried));
                history.Add(new Dictionary<string, string> { { "role", "assistant" }, { "content", reply } });
                pending.Pending = false;
                pending.Text = reply;
                pending.At = DateTime.Now;
            }
            catch (Exception ex)
            {
                pending.Pending = false;
                pending.Text = "Hiba: " + ex.Message;
                pending.At = DateTime.Now;
            }
            finally
            {
                busyChat = false;
                stickToBottom = true;
                SaveStore();
                Invalidate();
            }
        }

        // ── memory + persistence ───────────────────────────────────────────
        // The chat survives closing the app: messages, the model-side history and the
        // facts the user asked to be remembered all sit in %APPDATA%\CortexAI\chat.json.
        static string StorePath()
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CortexAI");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "chat.json");
        }

        static readonly string[] MemoryTriggers =
        {
            "a nevem", "nevem ", "jegyezd", "emlékezz", "emlekezz", "ne felejtsd", "hívj", "hivj ",
            "szólíts", "szolits", "kedvenc", "szeretem", "utálom", "utalom", "vagyok ", "dolgozom",
            "tanulok", "célom", "celom", "lakom", "születtem", "szulettem"
        };

        static readonly string[] QuestionStarts =
        {
            "mi ", "ki ", "mit ", "hol ", "mikor ", "hogyan ", "miért ", "miert ",
            "mennyi ", "melyik ", "tudsz "
        };

        void TryRemember(string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            string clean = text.Replace("\n", " ").Trim();
            if (clean.Length < 6 || clean.EndsWith("?")) return;
            string low = clean.ToLowerInvariant();
            foreach (var q in QuestionStarts) if (low.StartsWith(q)) return;
            bool hit = false;
            foreach (var t in MemoryTriggers) if (low.Contains(t)) { hit = true; break; }
            if (!hit) return;
            if (clean.Length > 180) clean = clean.Substring(0, 180).Trim();
            foreach (var m in memory) if (m.ToLowerInvariant() == low) return;
            if (memory.Count >= 60) return;
            memory.Add(clean);
        }

        void SaveStore()
        {
            try
            {
                if (messages.Count == 0 && File.Exists(StorePath())) return;
                var rows = new List<Dictionary<string, object>>();
                foreach (var m in messages)
                {
                    if (m.Pending || string.IsNullOrEmpty(m.Text)) continue;
                    var row = new Dictionary<string, object>();
                    row["me"] = m.Me;
                    row["text"] = m.Text;
                    row["at"] = m.At.ToString("o");
                    rows.Add(row);
                }
                var payload = new Dictionary<string, object>();
                payload["messages"] = rows;
                payload["history"] = history;
                payload["memory"] = memory;
                payload["savedAt"] = DateTime.UtcNow.ToString("o");
                File.WriteAllText(StorePath(), Api.Serialize(payload), new UTF8Encoding(false));
            }
            catch { }
        }

        void LoadStore()
        {
            try
            {
                string path = StorePath();
                if (!File.Exists(path)) return;
                var dict = Api.Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
                if (dict == null) return;

                object rawMessages;
                if (dict.TryGetValue("messages", out rawMessages) && rawMessages is IList)
                {
                    foreach (var item in (IList)rawMessages)
                    {
                        var row = item as Dictionary<string, object>;
                        if (row == null) continue;
                        string text = row.ContainsKey("text") ? Convert.ToString(row["text"]) : null;
                        if (string.IsNullOrEmpty(text)) continue;
                        bool me = row.ContainsKey("me") && row["me"] is bool && (bool)row["me"];
                        var msg = new Msg { Me = me, Text = text };
                        DateTime at;
                        if (row.ContainsKey("at") && DateTime.TryParse(Convert.ToString(row["at"]), out at)) msg.At = at.ToLocalTime();
                        messages.Add(msg);
                    }
                }

                object rawHistory;
                if (dict.TryGetValue("history", out rawHistory) && rawHistory is IList)
                {
                    foreach (var item in (IList)rawHistory)
                    {
                        var row = item as Dictionary<string, object>;
                        if (row == null || !row.ContainsKey("role") || !row.ContainsKey("content")) continue;
                        history.Add(new Dictionary<string, string>
                        {
                            { "role", Convert.ToString(row["role"]) },
                            { "content", Convert.ToString(row["content"]) }
                        });
                    }
                }

                object rawMemory;
                if (dict.TryGetValue("memory", out rawMemory) && rawMemory is IList)
                {
                    foreach (var item in (IList)rawMemory)
                    {
                        string note = Convert.ToString(item);
                        if (!string.IsNullOrEmpty(note)) memory.Add(note);
                    }
                }
            }
            catch { }
        }

        async Task Generate()
        {
            string prompt = promptInput.Text.Trim();
            if (prompt.Length == 0 || busyImage) return;

            busyImage = true;
            statusLine = "Indítás…";
            statusColor = Tz.Muted;
            rendered = null;
            renderedBytes = null;
            Invalidate();

            try
            {
                string style = styleIds[styleIndex];
                string id = await Task.Run(() => Api.CreateImage(prompt, style));
                var started = DateTime.UtcNow;

                for (int i = 0; i < 90; i++)
                {
                    await Task.Delay(2000);
                    int secs = (int)(DateTime.UtcNow - started).TotalSeconds;
                    statusLine = "Festés… " + secs + " s";
                    Invalidate();

                    string url = null;
                    string status = null;
                    try { url = await Task.Run(() => Api.ImageStatus(id, out status)); }
                    catch { continue; }

                    if (status == "succeeded" && url != null)
                    {
                        statusLine = "Letöltés…";
                        Invalidate();
                        byte[] bytes = await Task.Run(() => Api.Download(url));
                        renderedBytes = bytes;
                        using (var ms = new MemoryStream(bytes))
                        {
                            var img = Image.FromStream(ms);
                            if (rendered != null) rendered.Dispose();
                            rendered = img;
                        }
                        var thumb = new Bitmap(rendered, 52, 52);
                        thumbs.Insert(0, thumb);
                        statusLine = "Kész · " + DateTime.Now.ToString("HH:mm");
                        statusColor = Tz.Ok;
                        return;
                    }
                    if (status == "failed" || status == "error")
                    {
                        statusLine = "A festés nem sikerült. Próbálj másik promptot.";
                        statusColor = Tz.Danger;
                        return;
                    }
                }
                statusLine = "Túl sokáig tart. Próbáld újra.";
                statusColor = Tz.Danger;
            }
            catch (Exception ex)
            {
                statusLine = ex.Message;
                statusColor = Tz.Danger;
            }
            finally
            {
                busyImage = false;
                Invalidate();
            }
        }

        void SaveRendered()
        {
            if (renderedBytes == null) return;
            using (var dialog = new SaveFileDialog())
            {
                dialog.Filter = "PNG kép|*.png";
                dialog.FileName = "cortex-void-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".png";
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    File.WriteAllBytes(dialog.FileName, renderedBytes);
                    statusLine = "Mentve: " + Path.GetFileName(dialog.FileName);
                    statusColor = Tz.Ok;
                    Invalidate();
                }
            }
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.V) && page == 1 && !promptInput.Focused) return base.ProcessCmdKey(ref msg, keyData);
            return base.ProcessCmdKey(ref msg, keyData);
        }
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            string start = args.Length > 0 ? args[0].ToLowerInvariant() : "chat";
            try { Application.Run(new Shell(start)); }
            catch (Exception ex)
            {
                MessageBox.Show(ex.ToString(), "Cortex AI", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
