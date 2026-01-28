import typer

app = typer.Typer(help="主程序幫助信息")
user_app = typer.Typer(help="用戶管理子命令")

# 將 user_app 掛載到主 app 下，命令名為 'user'
app.add_typer(user_app, name="user")

@user_app.command("create")
def user_create(name: str):
    """創建一個新用戶"""
    typer.echo(f"正在創建用戶: {name}")

@user_app.command("list")
def user_list():
    """列出所有用戶"""
    typer.echo("用戶列表: admin, guest, " + typer.style("kimi", fg=typer.colors.GREEN, bold=True))

@app.command()
def status():
    """查看系統狀態"""
    typer.echo("系統運行正常")

if __name__ == "__main__":
    app()
