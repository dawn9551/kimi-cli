import typer

app = typer.Typer()

@app.command()
def hello(
    name: str, 
    formal: bool = False, 
    count: int = typer.Option(1, help="Number of times to greet")
):
    """
    簡單的打招呼程序。
    
    name: 位置參數 (Argument)
    formal: 可選參數 (Option)，默認為 False
    count: 帶有幫助信息的自定義選項
    """
    print(f"exec hello func")
    for _ in range(count):
        if formal:
            typer.echo(f"Good day, Mr./Ms. {name}.")
        else:
            typer.echo(f"Hello {name}!")

if __name__ == "__main__":
    print(f"exec app func")
    app()
