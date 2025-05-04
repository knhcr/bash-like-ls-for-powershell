$BashLikeLsExecutables = @(
    ".exe", ".bat", ".cmd",".ps1", ".sh", 
    ".js", ".py", ".rb", ".pl", ".cs", ".vbs"
)

$BashLikeLsColorMap = @{
    "Directory" = [ConsoleColor]::DarkCyan
    "Executable" = [ConsoleColor]::Green
    "SymbolicLink" = [ConsoleColor]::Cyan
    "Other" = $Host.UI.RawUI.ForegroundColor # default font color
}

$BashLikeLsTypeIdMap = @{
    "Directory" = "/"
    "Executable" = "*"
    "SymbolicLink" = "@"
    "Other" = ""
}

$BashLikeLsHelpText = @"
bash-like-ls

Options:
-1     list one file per line
-f,F   append indicator (one of */@) to entries
-c,C   color the output.
-l,L   simply passes through to pwsh's default ls (Get-ChildItem).
       this option will be preferentially applied.
--help display this help message

Notice:
For redirect or pipe, you must use with the pass through option (-L)
or -1 option. Basically this function returns nothing, because this
function internally calls 'Write-Host' instead of 'Write-Output'.
When used with -1 (without -c) option, this function returns a string
array of the file names.
When used with -l option, this function simply calls Get-ChildItem, so
returns an array of FileSystemInfo objects.

Author:
knhcr
"@

# -----------------------------------------------------------------------------------------------------------------
enum FileType {
    Directory
    Executable
    SymbolicLink
    Other
}

Function Bash-Like-LS {
    # 引数パース
    function Get-Args ($orgArgs, $lsArgs) {
        $i = 0
        while ($i -lt $orgArgs.Count) {
            $arg = $orgArgs[$i]
            $arg = "$arg" # ls 1234 のように数字などを入力した場合文字列にキャストする必要あり
            if ($arg -eq "--help") {
                $lsArgs["showHelp"] = $true
                return
            }
            if ($arg.StartsWith("-")) {
                # 複数のオプションが結合されているか確認（例: -1F）
                foreach ($char in $arg.ToLower().Substring(1).ToCharArray()) {
                    switch ($char) {
                        "1" { $lsArgs["onePerLine"] = $true }
                        "l" { $lsArgs["longFormat"] = $true }
                        "f" { $lsArgs["showFileType"] = $true }
                        "c" { $lsArgs["setColor"] = $true }
                        # 不明なオプションは無視
                    }
                }
            } else {
                $lsArgs["path"] = $arg # -で始まらなければ path として扱う
            }
            $i++
        }
        # オプション優先順位処理（-lは-1より優先）
        if ($lsArgs["longFormat"]) {
            $lsArgs["onePerLine"] = $false
        }
    }    

    # ファイルタイプを取得
    function Get-FileType {
        param([System.IO.FileSystemInfo]$item)
    
        $name = $item.Name
        $type = [FileType]::Other
    
        # check type
        try {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                # Symlink ( Directory より先に判定する必要あり )
                $type = [FileType]::SymbolicLink
            }
            elseif ($item.PSIsContainer) {
                # Directory
                $type = [FileType]::Directory
            }
            elseif ($script:BashLikeLsExecutables -contains $item.Extension.ToLower()) {
                # Executable
                $type = [FileType]::Executable
            }
        } catch {
            # do nothing
        }
        return $type
    }

    
    # 表示幅計算
    function Get-StringDisplayWidth {
        param([string]$text)
        $width = 0
        foreach ($char in $text.ToCharArray()) {
            # East Asian Width判定
            $codepoint = [int][char]$char
            
            # East Asian Full Width (F), Wide (W) の文字か判定
            $isWide = $false
            
            # CJK統合漢字, ひらがな, カタカナ, 全角記号など
            if (($codepoint -ge 0x1100 -and $codepoint -le 0x11FF) -or  # ハングル字母
                ($codepoint -ge 0x2E80 -and $codepoint -le 0x9FFF) -or  # CJK統合漢字など
                ($codepoint -ge 0xAC00 -and $codepoint -le 0xD7AF) -or  # ハングル音節
                ($codepoint -ge 0xF900 -and $codepoint -le 0xFAFF) -or  # CJK互換漢字
                ($codepoint -ge 0xFF01 -and $codepoint -le 0xFF60) -or  # 全角ASCII, 全角記号
                ($codepoint -ge 0xFFE0 -and $codepoint -le 0xFFE6)) {   # 全角記号
                $isWide = $true
            }
            
            if ($isWide) {
                $width += 2
            } else {
                $width += 1
            }
        }
        return $width
    }

    # 直接の引数文字列 $args をパース
    $lsArgs = @{
        "path" = "."  # path
        "onePerLine" = $false  # -1 オプション
        "longFormat" = $false  # -l オプション
        "showFileType" = $false  # -f オプション
        "setColor" = $false # -c オプション
        "showHelp" = $false # --help オプション
    }
    Get-Args $args $lsArgs

    # ヘルプ表示
    if ($lsArgs["showHelp"]) {
        Write-Output $script:BashLikeLsHelpText
        return
    }

    try {
        # ls -l : pwsh のデフォルト ls
        if ($lsArgs["longFormat"]) {
            Get-ChildItem -Path $lsArgs["path"] -ErrorAction Stop
            return
        } 
        
        # ls -1 : 1行ずつ
        if ($lsArgs["onePerLine"]) {
            $items = Get-ChildItem -Path $lsArgs["path"] -ErrorAction Stop
            if ($lsArgs["showFileType"]) {
                # -f あり
                if (-not $lsArgs["setColor"]){
                    # ls -1f
                    foreach ($item in $items) {
                        $type = Get-FileType -item $item
                        $displayName = $item.Name + $script:BashLikeLsTypeIdMap[$type.ToString()]
                        Write-Output $displayName
                    }
                    return
                }else{
                    # ls -1fc
                    foreach ($item in $items) {
                        $type = Get-FileType -item $item
                        $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap[$type.ToString()]
                        Write-Host -NoNewline $item.Name
                        $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap["Other"] # Default Color
                        Write-Host $script:BashLikeLsTypeIdMap[$type.ToString()]
                    }
                    return
                }
            } else {
                # -f 無し
                if (-not $lsArgs["setColor"]){
                    # ls -1
                    $items | Select-Object -ExpandProperty Name
                    return
                }else{
                    # ls -1c
                    foreach ($item in $items) {
                        $type = Get-FileType -item $item
                        $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap[$type.ToString()]
                        Write-Host -NoNewline $item.Name
                        $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap["Other"] # Default Color
                        Write-Host
                    }
                    return
                }
            }
        }
        
        # 以下 ls (複数カラム表示)

        $items = Get-ChildItem -Path $lsArgs["path"] -ErrorAction Stop
        if ($items.Count -eq 0) { return }
        
        # ファイル名配列 (width 計算のためにここで生成する必要あり)
        $names = @()
        $itemTypes = @()
        foreach ($item in $items) {
            # -f or -c のどちらかがある場合は type も取得
            if ($lsArgs["showFileType"] -or $lsArgs["setColor"]) {
                $type = Get-FileType -item $item
                $itemTypes += $type
            }
            if ($lsArgs["showFileType"]) {
                # ls -f
                $names += $item.Name + $script:BashLikeLsTypeIdMap[$type.ToString()]
            } else {
                # ls
                $names += $item.Name
            }
        }
        
        $width = $Host.UI.RawUI.WindowSize.Width
        
        # 各ファイル名の表示幅を取得
        $displayWidths = @($names | ForEach-Object { Get-StringDisplayWidth $_ })
        $maxWidth = ($displayWidths | Measure-Object -Maximum).Maximum
        $colWidth = $maxWidth + 2
        
        # 列数を計算
        $cols = [math]::Max(1, [math]::Floor($width / $colWidth))
        
        # 表示
        for ($i = 0; $i -lt $names.Count; $i++) {
            $name = $names[$i]
            $displayWidth = $displayWidths[$i]
            $padding = $colWidth - $displayWidth
            
            if ($lsArgs["setColor"]) {
                # カラー表示
                $type = $itemTypes[$i]
                
                if ($lsArgs["showFileType"]) {
                    # ls -fc: ファイル名のみを色付けし、タイプ記号はデフォルト色
                    $baseName = $items[$i].Name
                    $typeSymbol = $script:BashLikeLsTypeIdMap[$type.ToString()]
                    
                    # ファイル名を色付け
                    $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap[$type.ToString()]
                    Write-Host -NoNewline $baseName
                    
                    # タイプ記号はデフォルト色
                    $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap["Other"]
                    Write-Host -NoNewline $typeSymbol
                } else {
                    # ls -c: 通常の色付け
                    $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap[$type.ToString()]
                    Write-Host -NoNewline $name
                }
                
                # 色をデフォルトに戻す
                $Host.UI.RawUI.ForegroundColor = $script:BashLikeLsColorMap["Other"]
            } else {
                # 色付けなし
                Write-Host -NoNewline $name
            }
            
            if ($padding -gt 0) {
                Write-Host -NoNewline (" " * $padding)
            }
            
            if (($i + 1) % $cols -eq 0 -or $i -eq $names.Count - 1) { 
                Write-Host ""
            }
        }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error -Message "Get-ChildItem: $_" -Category ObjectNotFound -ErrorAction Continue
    }
}