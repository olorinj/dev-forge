package main

import (
	"crypto/md5"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
)

type HashOutput struct {
	Source string `json:"source"`
	Sha256 string `json:"sha256"`
	Md5    string `json:"md5"`
}

func computeHashes(data []byte) (string, string) {
	s := sha256.Sum256(data)
	m := md5.Sum(data)
	return hex.EncodeToString(s[:]), hex.EncodeToString(m[:])
}

func printResult(source, sha, md string, asJSON bool) {
	if asJSON {
		out := HashOutput{Source: source, Sha256: sha, Md5: md}
		b, _ := json.Marshal(out)
		fmt.Println(string(b))
	} else {
		fmt.Println("==================================================")
		fmt.Println("  HashForge (Go) - Resultados de Hashing")
		fmt.Println("==================================================")
		fmt.Printf("  Fuente:  %s\n", source)
		fmt.Printf("  SHA-256: %s\n", sha)
		fmt.Printf("  MD5:     %s\n", md)
		fmt.Println("==================================================")
	}
}

func main() {
	stringFlag := flag.String("string", "", "Calcula los hashes del texto especificado")
	flag.StringVar(stringFlag, "s", "", "Alias de -string")

	fileFlag := flag.String("file", "", "Calcula los hashes del archivo especificado")
	flag.StringVar(fileFlag, "f", "", "Alias de -file")

	jsonFlag := flag.Bool("json", false, "Salida en formato JSON")
	flag.BoolVar(jsonFlag, "j", false, "Alias de -json")

	flag.Parse()

	if *stringFlag != "" {
		s, m := computeHashes([]byte(*stringFlag))
		printResult(*stringFlag, s, m, *jsonFlag)
		return
	}

	if *fileFlag != "" {
		data, err := os.ReadFile(*fileFlag)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error leyendo archivo '%s': %v\n", *fileFlag, err)
			os.Exit(1)
		}
		s, m := computeHashes(data)
		printResult(*fileFlag, s, m, *jsonFlag)
		return
	}

	// Sin argumentos: demostración por defecto
	sample := "dev-forge test"
	s, m := computeHashes([]byte(sample))
	printResult(sample, s, m, *jsonFlag)
}
