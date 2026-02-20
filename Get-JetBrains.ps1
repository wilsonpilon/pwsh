$apps = @("JetBrains.CLion", "JetBrains.DataGrip", "JetBrains.GoLand", "JetBrains.RustRover", "JetBrains.PyCharm", "JetBrains.PhpStorm", "JetBrains.WebStorm", "JetBrains.Rider", "JetBrains.IntelliJIDEA")

foreach ($app in $apps) { winget install $app -e }