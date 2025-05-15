$BashLikeLsExecutables = @(
    ".exe", ".bat", ".cmd",".ps1", ".sh", 
    ".js", ".py", ".rb", ".pl", ".cs", ".vbs"
)

$BashLikeLsSpaceLength = 2

$ANSI_ESC = [char]0x1B
$ANSI_RESET = "$ANSI_ESC[0m"
$BashLikeLsColorMap = @{
    "Directory"    = "$ANSI_ESC[94m" # 明るい青
    "Executable"   = "$ANSI_ESC[32m" # 緑
    "SymbolicLink" = "$ANSI_ESC[36m" # シアン
    "Other"        = $ANSI_RESET     # reset color and styles
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
or -1 without -F, -C option. 
When used with -L option, this function simply calls Get-ChildItem,
so returns an array of FileSystemInfo objects.
When used with -1 option, this function returns a string array of the
file names.

Version : 1.0.1
Author: knhcr
"@

# -----------------------------------------------------------------------------------------------------------------
$BashLikeLsDebugFlag = $false

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

    
    # 各アイテムの表示幅を計算
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

    # 行列数計算 (ret : 整形後の行数, 整形後の列数, 各列の幅(padding 含まず))
    function Get-LineCount($displayWidths, $windowWidth, $padding=$null) {
        if($padding -eq $null){ $padding = $script:BashLikeLsSpaceLength }

        $rows = $displayWidths.Count # 整形後の行数 [return]
        $cols = 1                    # 整形後の列数 [return]
        $colWidths = @()             # 整形後の各列の幅 [return]


        # 指定された列数で並べた場合の横の長さを計算
        function calc-width($displayWidths, $padding, $cols){
            $ret = 0
            $maxWidths = @() # 各列の最大幅
            $perLines = [math]::Ceiling($displayWidths.Count / $cols) # 1列当たりの要素数
            for ($i = 0; $i -lt $cols; $i++) {
                # 縦の列毎に最大長を取得
                $startIdx = $i * $perLines
                $endIdx = [math]::Min($i * $perLines + $perLines -1, $displayWidths.Count - 1)

                #if($script:BashLikeLsDebugFlag){
                #    Write-Host "[$startIdx`:$endIdx]"
                #}

                $max = ($displayWidths[$startIdx..$endIdx] | Measure-Object -Maximum).Maximum
                $maxWidths += $max
            }
            # padding も含めた1行当たりの幅 を計算
            $sum = ($maxWidths | Measure-Object -Sum).Sum
            $ret = $sum + ($cols - 1) * $padding
            return @($ret, $maxWidths)
        }

        
        # window 幅を超えるまで列数を増やして幅を計算し、はみ出る直前の列数を取得
        $max = ($displayWidths| Measure-Object -Maximum).Maximum
        $colWidths = @($max)
        while($true){
            $nextCols = $cols + 1

            #if($script:BashLikeLsDebugFlag){
            #    Write-Host "nextCols : $nextCols"
            #}

            if ($nextCols -gt $displayWidths.Count) { # 1行で全て納まる場合ここ
                break
            }
            $tmpWidth, $tmpColWidths = calc-width $displayWidths $padding $nextCols
            if ($tmpWidth -gt $windowWidth) {
                break
            }
            $colWidths = $tmpColWidths
            $cols = $nextCols
        }
        $rows = [math]::Ceiling($displayWidths.Count / $cols)
        return @($rows, $cols, $colWidths)
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
        # ls -l : pwsh のデフォルト ls にパススルー
        if ($lsArgs["longFormat"]) {
            Get-ChildItem -Path $lsArgs["path"] -ErrorAction Stop
            return
        } 
        
        # -- メインの処理 --
        $items = Get-ChildItem -Path $lsArgs["path"] -ErrorAction Stop
        if($script:BashLikeLsDebugFlag){
            Write-Host "items count : "$items.Count
        }

        if ($items.Count -eq 0) { return }

        $displayNames = @()
        $fileTypes = @()

        # f も c も無し : type 不要
        if ((-not $lsArgs["showFileType"]) -and (-not $lsArgs["setColor"])) {
            $displayNames = $items | Select-Object -ExpandProperty Name
        }
        # f か c 有り : type 取得
        else {
            foreach ($item in $items) {
                # ファイルタイプ取得
                $type = Get-FileType -item $item
                $fileTypes += $type

                # f の場合タイプ識別子を追加
                if ($lsArgs["showFileType"]) {
                    $displayNames += $item.Name + $script:BashLikeLsTypeIdMap[$type.ToString()]
                }
            }
        }

        # -1 で表示
        if ($lsArgs["onePerLine"]) {
            foreach ($name in $displayNames) {
                if ($lsArgs["setColor"]) {
                    $type = $fileTypes[$i]
                    if ($type -ne $script:FileType.Other) {
                        $name = $script:BashLikeLsColorMap[$type.ToString()] + $name + $script:ANSI_RESET
                    }
                }
                Write-Output $name
            }
            return
        }

        # -1 無し : 複数カラム表示
        # 行と列を計算
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
        $displayWidths = @($displayNames | ForEach-Object { Get-StringDisplayWidth $_ })
        $rows, $cols, $colWidths = Get-LineCount $displayWidths $windowWidth

        if($script:BashLikeLsDebugFlag){
            Write-Host "(row, col) = ($rows, $cols)"
            Write-Host "column widths = " $colWidths
            Write-Host "display names = " $displayNames
            Write-Host "each width = " $displayWidths
        }

        # 出力ラインを生成
        $lines = @()
        for ($i = 0; $i -lt $rows; $i++) {
            $lines += ,@() # ,を付けないと lines.push([]) ではなく lines.extend([]) になる
        }

        $tmpX = 0
        $tmpY = 0
        for ($idx=0; $idx -lt $displayNames.Count; $idx++ ){
            $name = $displayNames[$idx]
            $tmpX = [math]::Floor($idx / $rows) # 列
            $tmpY = $idx - ($tmpX * $rows) # 行
            
            # padding
            $name += (" " * ($colWidths[$tmpX] - $displayWidths[$idx]) -join "")

            # color
            if ($lsArgs["setColor"]) {
                $type = $fileTypes[$idx]
                if ($type -ne $script:FileType.Other) {
                    $name = $script:BashLikeLsColorMap[$type.ToString()] + $name + $script:ANSI_RESET
                }
            }

            $lines[$tmpY] += $name
        }

        # 出力
        $space = (" " * $script:BashLikeLsSpaceLength) -join ""
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $tmp = $lines[$i] -join $space
            Write-Output $tmp
        }
        return
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Error -Message "Get-ChildItem: $_" -Category ObjectNotFound -ErrorAction Continue
    }
}