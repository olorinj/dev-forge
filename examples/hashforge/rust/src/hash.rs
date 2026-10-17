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
            "3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
        );
        assert_eq!(res.md5, "253c885072f588436970bcbc0fe47b9e");
    }
}

