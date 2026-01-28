import typer

app = typer.Typer()

def interactive_shell(user_name: str):
    """
    這是一個簡單的交互循環，模擬 Kimi 的 Shell 模式。
    """
    typer.secho(f"--- 已進入 {user_name} 的交互模式 (輸入 'exit' 或 'quit' 退出) ---", fg=typer.colors.CYAN)
    
    while True:
        # 獲取用戶輸入
        text = typer.prompt(f"{user_name}:")
        
        # 處理退出邏輯
        if text.lower() in ["exit", "quit"]:
            typer.echo("再見！")
            break
            
        # 處理簡單命令
        if text.strip() == "":
            continue
            
        typer.secho(f"你輸入了: {text}", fg=typer.colors.GREEN)

@app.command()
def start(
    name: str = typer.Option("Guest", "--name", "-n", help="你的名字"),
    shell: bool = typer.Option(False, "--shell", "-s", help="是否進入交互模式")
):
    """
    啟動程序。如果帶有 --shell 參數，則進入交互模式。
    """
    typer.echo(f"正在啟動程序，你好 {name}...")
    
    if shell:
        interactive_shell(name)
    else:
        typer.echo("未開啟交互模式，程序執行完畢。")

if __name__ == "__main__":
    app()
