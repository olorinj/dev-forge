use md5::Md5;
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::{self, Read};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HashResult {
    pub sha256: String,
    pub md5: String,
}

pub fn hash_bytes(data: &[u8]) -> HashResult {
    let mut sha_hasher = Sha256::new();
    sha_hasher.update(data);
    let sha256 = hex::encode(sha_hasher.finalize());

    let mut md5_hasher = Md5::new();
    md5_hasher.update(data);
    let md5 = hex::encode(md5_hasher.finalize());

    HashResult { sha256, md5 }
}

pub fn hash_string(text: &str) -> HashResult {
    hash_bytes(text.as_bytes())
}

pub fn hash_file<P: AsRef<Path>>(path: P) -> io::Result<HashResult> {
    let mut file = File::open(path)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;
    Ok(hash_bytes(&buffer))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_string() {
        let res = hash_string("dev-forge test");
        assert_eq!(
            res.sha256,
            "7fa5a0fe7bcdd886b62fc0bcddbf1a70c86801bb61dd66c430485981ee8aa6bf"
        );
        assert_eq!(res.md5, "00dfa0bf846830cfcae67dca1f543166");
    }
}
