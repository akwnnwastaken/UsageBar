// This project enables both WPF and Windows Forms, and both frameworks (plus
// System.Drawing) are implicitly imported, so many type names are ambiguous.
// The user interface is WPF, so these aliases make the WPF meaning the default
// and an ambiguous name can never silently resolve to the wrong framework.
//
// Color, Pen and FontStyle are deliberately NOT aliased here: the tray icon is
// drawn with GDI+ and genuinely needs the System.Drawing versions. A global
// alias cannot be overridden at file scope (CS1537), so those three are aliased
// per file instead — see TrayIconRenderer.cs, AppTheme.cs and
// UsageHistoryChart.cs.

global using System.IO;

global using Application = System.Windows.Application;
global using Brush = System.Windows.Media.Brush;
global using Brushes = System.Windows.Media.Brushes;
global using Button = System.Windows.Controls.Button;
global using CheckBox = System.Windows.Controls.CheckBox;
global using Clipboard = System.Windows.Clipboard;
global using FontFamily = System.Windows.Media.FontFamily;
global using Orientation = System.Windows.Controls.Orientation;
global using Point = System.Windows.Point;
global using RadioButton = System.Windows.Controls.RadioButton;
