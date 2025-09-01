# FeeCalc.ps1 — offline WPF calculator for “customer covers the fees”
# Runs in STA for WPF, relaunches itself if needed.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
  $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -STA
  exit
}

Add-Type -AssemblyName PresentationFramework

# Presets (editable)
$presets = @(
  @{ Name='Custom';          Pct=0.0;  Fixed=0.00 },
  @{ Name='Stripe (2.9% + $0.30)';           Pct=2.9;  Fixed=0.30 },   # https://stripe.com/pricing
  @{ Name='Square Online (2.9% + $0.30)';    Pct=2.9;  Fixed=0.30 },   # https://squareup.com/us/en/pricing
  @{ Name='PayPal Checkout (3.49% + $0.49)'; Pct=3.49; Fixed=0.49 },   # https://www.paypal.com/us/business/paypal-business-fees
  @{ Name='Venmo Business (1.9% + $0.10)';   Pct=1.9;  Fixed=0.10 }    # https://help.venmo.com/cs/articles/business-profile-transaction-fees-vhel221
)

# XAML UI
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Fee Calculator 💸" Height="420" Width="560" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="What do you need to receive (after fees)?" FontSize="16" FontWeight="SemiBold"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,6,0,12">
      <TextBlock Text="$" VerticalAlignment="Center" FontSize="20" Margin="0,0,4,0"/>
      <TextBox x:Name="NetBox" Width="140" FontSize="20" Text="29.00"/>
    </StackPanel>

    <TextBlock Grid.Row="2" Text="Fee preset (or choose Custom and enter your own):" FontWeight="SemiBold"/>
    <ComboBox x:Name="PresetCombo" Grid.Row="3" Height="32" Margin="0,6,0,12"/>

    <Grid Grid.Row="4" Margin="0,0,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal">
        <TextBlock Text="Percent fee:" VerticalAlignment="Center" Margin="0,0,8,0"/>
        <TextBox x:Name="PctBox" Width="100" Text="2.9"/>
        <TextBlock Text="%" VerticalAlignment="Center" Margin="6,0,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <TextBlock Text="Fixed fee:" VerticalAlignment="Center" Margin="12,0,8,0"/>
        <TextBlock Text="$" VerticalAlignment="Center"/>
        <TextBox x:Name="FixedBox" Width="100" Text="0.30" Margin="4,0,0,0"/>
      </StackPanel>
    </Grid>

    <StackPanel Grid.Row="5">
      <Button x:Name="CalcBtn" Content="🧮 Calculate" Height="40" FontSize="16" />
      <Border Margin="0,12,0,0" Padding="12" CornerRadius="10" Background="#FFF6F8FF" BorderBrush="#FFCBD5E1" BorderThickness="1">
        <StackPanel>
          <TextBlock x:Name="OutCharge" FontSize="24" FontWeight="Bold" Text="Charge customer: —"/>
          <TextBlock x:Name="OutYouGet" Margin="0,6,0,0" Text="You receive (after fees): —"/>
          <TextBlock x:Name="OutFees"    Margin="0,2,0,0" Text="Customer covers fees: —"/>
        </StackPanel>
      </Border>
    </StackPanel>

    <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="CopyBtn" Content="Copy amount" Margin="0,0,8,0"/>
      <Button x:Name="ResetBtn" Content="Reset"/>
    </StackPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Grab controls
$NetBox     = $window.FindName('NetBox')
$PctBox     = $window.FindName('PctBox')
$FixedBox   = $window.FindName('FixedBox')
$PresetCombo= $window.FindName('PresetCombo')
$RoundUpBox = $window.FindName('RoundUpBox')
$CalcBtn    = $window.FindName('CalcBtn')
$CopyBtn    = $window.FindName('CopyBtn')
$ResetBtn   = $window.FindName('ResetBtn')
$OutCharge  = $window.FindName('OutCharge')
$OutYouGet  = $window.FindName('OutYouGet')
$OutFees    = $window.FindName('OutFees')

# Load presets into ComboBox
$presets | ForEach-Object { [void]$PresetCombo.Items.Add($_.Name) }
$PresetCombo.SelectedIndex = 1  # default to Stripe

function Parse-Decimal([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  $n = 0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Number, [CultureInfo]::InvariantCulture, [ref]$n)) { return [double]$n }
  return $null
}

function Compute-Gross([double]$needNet, [double]$pct, [double]$fixed, [bool]$roundUp) {
  if ($pct -ge 100) { throw "Percent fee must be less than 100%." }
  $grossExact = ($needNet + $fixed) / (1 - $pct/100)
  $gross = if ($roundUp) { [Math]::Ceiling($grossExact * 100.0) / 100.0 } else { [Math]::Round($grossExact,2) }
  $fees  = [Math]::Round(($gross * $pct/100) + $fixed, 2)
  $net   = [Math]::Round($gross - $fees, 2)
  return [pscustomobject]@{ Gross=$gross; Fees=$fees; Net=$net }
}

# Handlers
$PresetCombo.Add_SelectionChanged({
  $sel = $PresetCombo.SelectedItem
  $p = $presets | Where-Object { $_.Name -eq $sel }
  if ($null -ne $p) {
    $PctBox.Text   = [string]::Format([CultureInfo]::InvariantCulture, "{0:0.##}", $p.Pct)
    $FixedBox.Text = [string]::Format([CultureInfo]::InvariantCulture, "{0:0.00}", $p.Fixed)
  }
})

$Calc = {
  $needNet = Parse-Decimal $NetBox.Text
  $pct     = Parse-Decimal $PctBox.Text
  $fixed   = Parse-Decimal $FixedBox.Text
  if ($needNet -eq $null -or $pct -eq $null -or $fixed -eq $null) {
    [System.Windows.MessageBox]::Show("Please enter valid numbers (e.g., 29, 2.9, 0.30).","Input needed",'OK','Warning') | Out-Null
    return
  }
  try {
    $res = Compute-Gross -needNet $needNet -pct $pct -fixed $fixed -roundUp $true
    $OutCharge.Text = "Charge customer: $" + $res.Gross.ToString("0.00", [CultureInfo]::InvariantCulture)
    $OutYouGet.Text = "You receive (after fees): $" + $res.Net.ToString("0.00", [CultureInfo]::InvariantCulture)
    $OutFees.Text   = "Customer covers fees: $" + $res.Fees.ToString("0.00", [CultureInfo]::InvariantCulture)
  } catch {
    [System.Windows.MessageBox]::Show($_.Exception.Message,"Oops",'OK','Error') | Out-Null
  }
}

$CalcBtn.Add_Click($Calc)
$NetBox.Add_KeyDown({ if ($_.Key -eq 'Enter') { & $Calc } })
$PctBox.Add_KeyDown({ if ($_.Key -eq 'Enter') { & $Calc } })
$FixedBox.Add_KeyDown({ if ($_.Key -eq 'Enter') { & $Calc } })

$CopyBtn.Add_Click({
  if ($OutCharge.Text -match '([\d]+\.[\d]{2})') {
    [System.Windows.Clipboard]::SetText($Matches[1])
  }
})

$ResetBtn.Add_Click({
  $NetBox.Text   = "29.00"
  $PresetCombo.SelectedIndex = 1
  $RoundUpBox.IsChecked = $true
  & $Calc
})

# Do an initial calc
& $Calc

# Show the window
$window.ShowDialog() | Out-Null
