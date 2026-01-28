import typer
from typing import Annotated, Optional
from pathlib import Path
from enum import Enum

class Color(str, Enum):
    red = "red"
    green = "green"
    blue = "blue"

app = typer.Typer()

@app.command()
def config(
    # 路徑驗證：必須存在且必須是文件
    file_path: Annotated[Path, typer.Argument(exists=True, file_okay=True, dir_okay=False, readable=True)],
    # 數值範圍限制
    retry: Annotated[int, typer.Option(min=0, max=5)] = 3,
    # 枚舉類型自動生成選單
    theme: Color = Color.red,
    # 可選字符串
    note: Annotated[Optional[str], typer.Option(help="備註信息")] = None
):
    """
    演示強類型驗證。
    """
    typer.echo(f"讀取文件: {file_path}")
    typer.echo(f"重試次數: {retry}")
    typer.echo(f"選定主題: {theme.value}")
    if note:
        typer.echo(f"備註: {note}")

if __name__ == "__main__":
    app()
