#!/usr/bin/env python3
"""Execute the actual recommended cancellation example against in-memory I/O."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TESTS = r'''
#[tokio::test]
async fn eof_and_closed_channel_terminate() -> std::io::Result<()> {
    use tokio::io::AsyncWriteExt;
    for (bytes, expected) in [(0, None), (17, Some(std::io::ErrorKind::UnexpectedEof)), (1024, None)] {
        let (mut writer, mut reader) = tokio::io::duplex(2048);
        writer.write_all(&vec![7; bytes]).await?;
        writer.shutdown().await?;
        let (tx, mut rx) = tokio::sync::mpsc::channel(1);
        drop(tx);
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(2), good_example(&mut reader, &mut rx, |_| {}),
        ).await.expect("closed inputs must not spin");
        assert_eq!(result.err().map(|error| error.kind()), expected);
    }
    Ok(())
}

#[tokio::test]
async fn partial_read_survives_message_branch() -> std::io::Result<()> {
    use std::future::Future;
    use std::task::{Context, Poll};
    use tokio::io::AsyncWriteExt;
    let (mut writer, mut reader) = tokio::io::duplex(2048);
    let (tx, mut rx) = tokio::sync::mpsc::channel(1);
    writer.write_all(&[7; 17]).await?;
    let mut frames = Vec::new();
    {
    let mut operation = std::pin::pin!(good_example(&mut reader, &mut rx, |frame| frames.push(frame.to_vec())));
    let waker = futures::task::noop_waker();
    let mut context = Context::from_waker(&waker);
    // Consume the prefix, then suspend waiting for either more bytes or a message.
    assert!(matches!(operation.as_mut().poll(&mut context), Poll::Pending));
    tx.send(9).await.expect("receiver alive");
    assert!(matches!(operation.as_mut().poll(&mut context), Poll::Pending));
    writer.write_all(&[8; 1007]).await?;
    writer.write_all(&[9; 1024]).await?;
    writer.shutdown().await?;
    tokio::time::timeout(std::time::Duration::from_secs(2), operation)
        .await.expect("complete frame followed by EOF must terminate")?;
    }
    assert_eq!(frames, vec![[vec![7; 17], vec![8; 1007]].concat(), vec![9; 1024]]);
    Ok(())
}
'''


def main():
    source = (ROOT / "rules/async-cancel-safety.md").read_text()
    section = source.split("## Good\n", 1)[1].split("\n## ", 1)[0]
    example = re.search(r"```rust\n(.*?)\n```", section, re.DOTALL)
    if example is None:
        raise SystemExit("missing recommended cancellation example")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(example.group(1) + "\n" + TESTS, encoding="utf-8")


if __name__ == "__main__":
    main()
