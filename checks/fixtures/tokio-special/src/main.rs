use tokio::runtime::Handle;

fn report_unstable_metrics() {
    let metrics = Handle::current().metrics();
    println!("blocking queue: {}", metrics.blocking_queue_depth());
    println!("blocking threads: {}", metrics.num_blocking_threads());
    println!("worker 0 polls: {}", metrics.worker_poll_count(0));
}

async fn run_app() {
    tokio::task::yield_now().await;
}

#[tokio::main]
async fn main() {
    console_subscriber::init();
    report_unstable_metrics();
    run_app().await;
}
