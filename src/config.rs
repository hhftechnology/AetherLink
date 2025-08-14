use anyhow::{Context, Result};
use ed25519_dalek::SigningKey;
use ed25519_dalek::pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding};
use iroh_base::key::SecretKey;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub identity: Option<Identity>,
    pub servers: HashMap<String, String>,
    pub default_server: Option<String>,
    pub tunnels: Vec<TunnelConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Identity {
    #[serde(with = "secret_key_serde")]
    pub secret_key: SecretKey,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TunnelConfig {
    pub domain: String,
    pub local_port: u16,
    pub enabled: bool,
}

impl Config {
    pub fn load(config_dir: &Path) -> Result<Self> {
        let config_file = config_dir.join("config.toml");
        
        if config_file.exists() {
            let contents = std::fs::read_to_string(&config_file)
                .with_context(|| format!("Failed to read config file: {:?}", config_file))?;
            toml::from_str(&contents)
                .with_context(|| "Failed to parse config file")
        } else {
            Ok(Self::default())
        }
    }

    pub fn save(&self, config_dir: &Path) -> Result<()> {
        let config_file = config_dir.join("config.toml");
        let contents = toml::to_string_pretty(self)
            .context("Failed to serialize config")?;
        std::fs::write(&config_file, contents)
            .with_context(|| format!("Failed to write config file: {:?}", config_file))?;
        Ok(())
    }

    pub fn resolve_server(&self, name_or_id: &str) -> Result<String> {
        // Check if it's already a node ID
        if name_or_id.starts_with("node") || name_or_id.len() == 52 {
            return Ok(name_or_id.to_string());
        }
        
        // Check if it's an alias
        self.servers.get(name_or_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Unknown server: {}", name_or_id))
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            identity: None,
            servers: HashMap::new(),
            default_server: None,
            tunnels: Vec::new(),
        }
    }
}

impl Identity {
    pub fn generate() -> Self {
        let secret_key = SecretKey::generate();
        Self { secret_key }
    }

    pub fn node_id(&self) -> String {
        format!("{}", self.secret_key.public())
    }

    pub fn from_file(path: &Path) -> Result<Self> {
        let pem = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read identity file: {:?}", path))?;
        let signing_key = SigningKey::from_pkcs8_pem(&pem)
            .context("Failed to parse identity key")?;
        let bytes = signing_key.to_bytes();
        let secret_key = SecretKey::from_bytes(&bytes);
        Ok(Self { secret_key })
    }

    pub fn to_file(&self, path: &Path) -> Result<()> {
        let bytes = self.secret_key.to_bytes();
        let signing_key = SigningKey::from_bytes(&bytes);
        let pem = signing_key.to_pkcs8_pem(LineEnding::default())
            .context("Failed to encode identity key")?;
        std::fs::write(path, pem.as_bytes())
            .with_context(|| format!("Failed to write identity file: {:?}", path))?;
        Ok(())
    }
}

mod secret_key_serde {
    use super::*;
    use serde::{Deserializer, Serializer};
    use base64::{Engine as _, engine::general_purpose::STANDARD};

    pub fn serialize<S>(key: &SecretKey, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let bytes = key.to_bytes();
        let encoded = STANDARD.encode(&bytes);
        serializer.serialize_str(&encoded)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<SecretKey, D::Error>
    where
        D: Deserializer<'de>,
    {
        let encoded = String::deserialize(deserializer)?;
        let bytes = STANDARD.decode(&encoded)
            .map_err(serde::de::Error::custom)?;
        let bytes_32: [u8; 32] = bytes.try_into()
            .map_err(|_| serde::de::Error::custom("Invalid key length"))?;
        Ok(SecretKey::from_bytes(&bytes_32))
    }
}

pub struct Auth {
    auth_dir: std::path::PathBuf,
}

impl Auth {
    pub fn new(config_dir: &Path) -> Result<Self> {
        let auth_dir = config_dir.join("auth");
        std::fs::create_dir_all(&auth_dir)?;
        Ok(Self { auth_dir })
    }

    pub fn is_authorized(&self, node_id: &str) -> bool {
        self.auth_dir.join(node_id).exists()
    }

    pub fn authorize(&self, node_id: &str) -> Result<()> {
        std::fs::write(self.auth_dir.join(node_id), "")?;
        Ok(())
    }

    pub fn revoke(&self, node_id: &str) -> Result<()> {
        let path = self.auth_dir.join(node_id);
        if path.exists() {
            std::fs::remove_file(path)?;
        }
        Ok(())
    }
}