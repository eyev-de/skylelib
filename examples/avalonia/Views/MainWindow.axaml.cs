using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using SkyleAvaloniaExample.ViewModels;

namespace SkyleAvaloniaExample.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);

    private void OnCalibrateClick(object? sender, RoutedEventArgs e)
        => (DataContext as MainViewModel)?.StartHostCalibration();
}
