use askama::Template;
use axum::{response::Html, routing::get, Router};
use tower_http::services::ServeDir;

#[derive(Template)]
#[template(path = "home.html")]
struct HomeTemplate;

#[derive(Template)]
#[template(path = "about.html")]
struct AboutTemplate;

#[derive(Template)]
#[template(path = "contact.html")]
struct ContactTemplate;

async fn home() -> Html<String> {
    Html(HomeTemplate.render().unwrap())
}

async fn about() -> Html<String> {
    Html(AboutTemplate.render().unwrap())
}

async fn contact() -> Html<String> {
    Html(ContactTemplate.render().unwrap())
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let bind_addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:3000".to_string());

    let app = Router::new()
        .route("/", get(home))
        .route("/about", get(about))
        .route("/contact", get(contact))
        .nest_service("/static", ServeDir::new("static"));

    let listener = tokio::net::TcpListener::bind(&bind_addr).await.unwrap();
    tracing::info!("Listening on {bind_addr}");
    axum::serve(listener, app).await.unwrap();
}
