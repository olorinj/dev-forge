#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#pragma comment(lib, "advapi32.lib")

static int compute_hashes(const unsigned char *data, size_t len, char *sha_hex, char *md5_hex) {
    HCRYPTPROV hProv = 0;
    HCRYPTHASH hHash = 0;
    BYTE hash[32];
    DWORD hashLen = 32;

    if (!CryptAcquireContext(&hProv, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT))
        return 0;

    // SHA-256
    if (CryptCreateHash(hProv, CALG_SHA_256, 0, 0, &hHash)) {
        CryptHashData(hHash, data, (DWORD)len, 0);
        CryptGetHashParam(hHash, HP_HASHVAL, hash, &hashLen, 0);
        CryptDestroyHash(hHash);
        for (DWORD i = 0; i < hashLen; i++) sprintf(sha_hex + i * 2, "%02x", hash[i]);
        sha_hex[hashLen * 2] = '\0';
    }

    // MD5
    hashLen = 16;
    if (CryptCreateHash(hProv, CALG_MD5, 0, 0, &hHash)) {
        CryptHashData(hHash, data, (DWORD)len, 0);
        CryptGetHashParam(hHash, HP_HASHVAL, hash, &hashLen, 0);
        CryptDestroyHash(hHash);
        for (DWORD i = 0; i < hashLen; i++) sprintf(md5_hex + i * 2, "%02x", hash[i]);
        md5_hex[hashLen * 2] = '\0';
    }

    CryptReleaseContext(hProv, 0);
    return 1;
}

#else
#include <openssl/evp.h>

static int compute_hashes(const unsigned char *data, size_t len, char *sha_hex, char *md5_hex) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int hash_len;

    // SHA-256
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), NULL);
    EVP_DigestUpdate(ctx, data, len);
    EVP_DigestFinal_ex(ctx, hash, &hash_len);
    EVP_MD_CTX_free(ctx);
    for (unsigned int i = 0; i < hash_len; i++) sprintf(sha_hex + i * 2, "%02x", hash[i]);
    sha_hex[hash_len * 2] = '\0';

    // MD5
    ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_md5(), NULL);
    EVP_DigestUpdate(ctx, data, len);
    EVP_DigestFinal_ex(ctx, hash, &hash_len);
    EVP_MD_CTX_free(ctx);
    for (unsigned int i = 0; i < hash_len; i++) sprintf(md5_hex + i * 2, "%02x", hash[i]);
    md5_hex[hash_len * 2] = '\0';

    return 1;
}
#endif

static void print_result(const char *source, const char *sha, const char *md5, int as_json) {
    if (as_json) {
        printf("{\"source\": \"%s\", \"sha256\": \"%s\", \"md5\": \"%s\"}\n", source, sha, md5);
    } else {
        printf("==================================================\n");
        printf("  HashForge (C) - Resultados de Hashing\n");
        printf("==================================================\n");
        printf("  Fuente:  %s\n", source);
        printf("  SHA-256: %s\n", sha);
        printf("  MD5:     %s\n", md5);
        printf("==================================================\n");
    }
}

int main(int argc, char *argv[]) {
    const char *string_input = NULL;
    const char *file_input = NULL;
    int as_json = 0;

    for (int i = 1; i < argc; i++) {
        if ((strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--string") == 0) && i + 1 < argc) {
            string_input = argv[++i];
        } else if ((strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--file") == 0) && i + 1 < argc) {
            file_input = argv[++i];
        } else if (strcmp(argv[i], "-j") == 0 || strcmp(argv[i], "--json") == 0) {
            as_json = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("Uso: hashforge-c [-s <texto> | -f <fichero>] [-j]\n");
            return 0;
        }
    }

    char sha[65], md5[33];

    if (string_input) {
        compute_hashes((const unsigned char *)string_input, strlen(string_input), sha, md5);
        print_result(string_input, sha, md5, as_json);
        return 0;
    }

    if (file_input) {
        FILE *f = fopen(file_input, "rb");
        if (!f) {
            fprintf(stderr, "Error al abrir el archivo '%s'\n", file_input);
            return 1;
        }
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fseek(f, 0, SEEK_SET);
        unsigned char *buf = (unsigned char *)malloc(sz);
        if (!buf) { fclose(f); return 1; }
        size_t read_bytes = fread(buf, 1, sz, f);
        fclose(f);
        compute_hashes(buf, read_bytes, sha, md5);
        free(buf);
        print_result(file_input, sha, md5, as_json);
        return 0;
    }

    const char *sample = "dev-forge test";
    compute_hashes((const unsigned char *)sample, strlen(sample), sha, md5);
    print_result(sample, sha, md5, as_json);
    return 0;
}

