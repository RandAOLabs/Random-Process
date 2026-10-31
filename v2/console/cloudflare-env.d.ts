declare namespace Cloudflare {
  interface Env {
    DB?: D1Database;
    BUCKET?: R2Bucket;
    RNG_NODE_URL?: string;
    RNG_BEACON_ID?: string;
    RNG_TOKEN_ID?: string;
    RNG_NETWORK_LABEL?: string;
  }
}
