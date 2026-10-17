use std::sync::Arc;

use tokio_cron_scheduler::{Job, JobScheduler};
use tracing::{error, info};

use crate::handlers::{self, AppState};

pub async fn start_scheduler(state: Arc<AppState>) -> anyhow::Result<JobScheduler> {
    let sched = JobScheduler::new().await?;

    let state_clone = state.clone();
    let job = Job::new_async("0 30 21 * * Tue-Sat", move |_uuid, _l| {
        let st = state_clone.clone();
        Box::pin(async move {
            info!("Starting scheduled daily-check and earnings-check batch jobs...");
            if let Err(err) = handlers::execute_daily_check(&st).await {
                error!("Scheduled daily-check failed: {}", err);
            }
            if let Err(err) = handlers::execute_earnings_check(&st, false).await {
                error!("Scheduled earnings-check failed: {}", err);
            }
            info!("Completed scheduled daily-check and earnings-check batch jobs.");
        })
    })?;

    sched.add(job).await?;
    sched.start().await?;
    info!("Cron scheduler started with schedule: '0 30 21 * * Tue-Sat' (UTC)");

    Ok(sched)
}
