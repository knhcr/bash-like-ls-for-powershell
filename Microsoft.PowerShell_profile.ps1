# Disable Bell Sound
Set-PSReadlineOption -BellStyle None

# Emacs Keybind
Set-PSReadlineOption -EditMode Emacs
Set-PSReadlineKeyHandler -Key Ctrl+d -Function DeleteChar

# History Completion
Set-PSReadLineOption -PredictionSource History

# Load virtualenv auto-activate script
. "$HOME\Documents\PowerShell\userScripts\virtualenv-auto-activate.ps1"

# venv 名表示 : vscode の 自動アクティベートで PS1 に表示されないため venv 名を強制表示
#function global:prompt {
#    # 初期プロンプト文字列（デフォルトのプロンプト）
#    $origPrompt = "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
#    
#    # 現在のプロンプトが既に venv 表示を含んでいるか確認
#    if ($env:VIRTUAL_ENV -and -not ($origPrompt -match "^\([^)]+\)")) {
#        $venvName = Split-Path $env:VIRTUAL_ENV -Leaf
#        # venv 名をプロンプトの先頭に表示（二重表示を防止）
#        "($venvName) $origPrompt"
#    } else {
#        # 既に venv 表示がある場合はそのまま返す
#        $origPrompt
#    }
#}

# cd to ~
#cd C:\cygwin64\home\user

# Clear Finished or Failed jobs
function Clear-Jobs {
    Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job
    Get-Job | Where-Object { $_.State -eq 'Failed' } | Remove-Job
}

# Update PATH Envirionment for current OS settings
function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariables('Machine').Path + ';' + [System.Environment]::GetEnvironmentVariables('User').Path
}

# Aliases
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String
Set-Alias -Name code -Value "C:\Program Files\VSCode\Code.exe"

# pwsh のコマンド履歴を編集
function Edit-History {
    $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    vscode $historyPath
}

# vscode でファイルを開く
function VSCODE ($file) {
    code $file *> $null # 標準出力、エラー出力を破棄
}

function _home {
    cd $env:home
}

function _projects {
    cd "g:\projects"
}

# Run script by only its file name. (e.g. foo.py args -> python foo.py args)
# [Requires] The target extension must not be associated with any executable by OS.
$ExecutionContext.InvokeCommand.CommandNotFoundAction = {
    param($CommandName, $CommandLookupEventArgs)
    
    $scriptMap = @{
        '\.py$' = 'python'
        '\.js$' = 'node'
        '\.pl$' = 'perl'
        '\.cs$' = 'dotnet script'
    }

    foreach ($ext in $scriptMap.Keys) {
        if ($CommandName -match $ext -and (Test-Path $CommandName)) {
            $interpreter = $scriptMap[$ext]
            $CommandLookupEventArgs.CommandScriptBlock = {
                & $interpreter $CommandName @args
            }.GetNewClosure()
            break
        }
    }
}

# PSReadLineのカスタム補完で.\を除去
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # 入力が空の場合、デフォルト補完を回避
    if (-not $wordToComplete) {
        return
    }

    # 一致するファイルを取得
    $completions = Get-ChildItem -Path "$wordToComplete*" -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.Extension -in @('.py', '.js', '.pl', '.cs') } | 
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_.Name,  # foo.py（パスなし）
                $_.Name,  # リスト表示
                'Command',  # コマンドとして扱う
                $_.FullName  # ツールチップにフルパス
            )
        }

    # 補完候補があれば返す、なければデフォルト補完を抑制
    if ($completions) {
        $completions
    }
}