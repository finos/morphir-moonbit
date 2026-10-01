///|
async fn main {
  @proton.asset(
    "Morphir Workbench",
    "frontend/dist/index.html",
    width=1280,
    height=860,
  )
  .load_config()
  .run_or_abort()
}
