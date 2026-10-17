#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#pragma comment(lib, "advapi32.lib")

bool compute_hashes(const unsigned char *data, size_t len, std::string &sha_hex, std::string &md5_hex) {
    HCRYPTPROV hProv = 0;
    HCRYPTHASH hHash = 0;
    BYTE hash[32];
    DWORD hashLen = 32;

    if (!CryptAcquireContext(&hProv, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT))
        return false;

    // SHA-256
    if (CryptCreateHash(hProv, CALG_SHA_256, 0, 0, &hHash)) {
        CryptHashData(hHash, data, static_cast<DWORD>(len), 0);
        CryptGetHashParam(hHash, HP_HASHVAL, hash, &hashLen, 0);
        CryptDestroyHash(hHash);
        std::ostringstream ss;
        for (DWORD i = 0; i < hashLen; i++) ss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
        sha_hex = ss.str();
    }

    // MD5
    hashLen = 16;
    if (CryptCreateHash(hProv, CALG_MD5, 0, 0, &hHash)) {
        CryptHashData(hHash, data, static_cast<DWORD>(len), 0);
        CryptGetHashParam(hHash, HP_HASHVAL, hash, &hashLen, 0);
        CryptDestroyHash(hHash);
        std::ostringstream ss;
        for (DWORD i = 0; i < hashLen; i++) ss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
        md5_hex = ss.str();
    }

    CryptReleaseContext(hProv, 0);
    return true;
}

#else
#include <openssl/evp.h>

bool compute_hashes(const unsigned char *data, size_t len, std::string &sha_hex, std::string &md5_hex) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int hash_len = 0;

    // SHA-256
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr);
    EVP_DigestUpdate(ctx, data, len);
    EVP_DigestFinal_ex(ctx, hash, &hash_len);
    EVP_MD_CTX_free(ctx);

    std::ostringstream ss_sha;
    for (unsigned int i = 0; i < hash_len; i++) ss_sha << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    sha_hex = ss_sha.str();

    // MD5
    ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_md5(), nullptr);
    EVP_DigestUpdate(ctx, data, len);
    EVP_DigestFinal_ex(ctx, hash, &hash_len);
    EVP_MD_CTX_free(ctx);

    std::ostringstream ss_md5;
    for (unsigned int i = 0; i < hash_len; i++) ss_md5 << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    md5_hex = ss_md5.str();

    return true;
}
#endif

void print_result(const std::string &source, const std::string &sha, const std::string &md5, bool as_json) {
    if (as_json) {
        std::cout << "{\"source\": \"" << source << "\", \"sha256\": \"" << sha << "\", \"md5\": \"" << md5 << "\"}\n";
    } else {
        std::cout << "==================================================\n";
        std::cout << "  HashForge (C++) - Resultados de Hashing\n";
        std::cout << "==================================================\n";
        std::cout << "  Fuente:  " << source << "\n";
        std::cout << "  SHA-256: " << sha << "\n";
        std::cout << "  MD5:     " << md5 << "\n";
        std::cout << "==================================================\n";
    }
}

int main(int argc, char *argv[]) {
    std::string string_input;
    std::string file_input;
    bool as_json = false;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if ((arg == "-s" || arg == "--string") && i + 1 < argc) {
            string_input = argv[++i];
        } else if ((arg == "-f" || arg == "--file") && i + 1 < argc) {
            file_input = argv[++i];
        } else if (arg == "-j" || arg == "--json") {
            as_json = true;
        } else if (arg == "-h" || arg == "--help") {
            std::cout << "Uso: hashforge-cpp [-s <texto> | -f <fichero>] [-j]\n";
            return 0;
        }
    }

    std::string sha, md5;

    if (!string_input.empty()) {
        compute_hashes(reinterpret_cast<const unsigned char*>(string_input.data()), string_input.size(), sha, md5);
        print_result(string_input, sha, md5, as_json);
        return 0;
    }

    if (!file_input.empty()) {
        std::ifstream file(file_input, std::ios::binary);
        if (!file) {
            std::cerr << "Error al abrir el archivo: " << file_input << "\n";
            return 1;
        }
        std::vector<unsigned char> buffer((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        compute_hashes(buffer.data(), buffer.size(), sha, md5);
        print_result(file_input, sha, md5, as_json);
        return 0;
    }

    std::string sample = "dev-forge test";
    compute_hashes(reinterpret_cast<const unsigned char*>(sample.data()), sample.size(), sha, md5);
    print_result(sample, sha, md5, as_json);
    return 0;
}
