import typer

app = typer.Typer()

def version_callback(value: bool):
    if value:
        typer.echo("Learning Typer Version: 1.0.0")
        raise typer.Exit()

@app.callback(invoke_without_command=True)
def main(
    ctx: typer.Context,
    verbose: bool = typer.Option(False, "--verbose", "-v", help="顯示詳細日誌"),
    version: bool = typer.Option(None, "--version", callback=version_callback, is_eager=True)
):
    """
    這裡處理全局參數。
    is_eager=True 確保 version 優先於其他參數被處理並觸發回調。
    """
    if verbose:
        typer.echo("已開啟詳細模式")
    
    # 如果沒有輸入任何子命令，顯示幫助信息
    if ctx.invoked_subcommand is None:
        typer.echo("歡迎使用演示工具，請輸入一個命令。")

@app.command()
def sync():
    typer.echo("正在同步數據...")

if __name__ == "__main__":
    app()
