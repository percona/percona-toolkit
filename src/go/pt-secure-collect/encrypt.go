package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
)

func encryptorCmd(opts *cliOptions) (err error) {
	password := sha256.Sum256([]byte(*opts.EncryptPassword))

	switch opts.Command {
	case "decrypt":
		if *opts.DecryptOutFile == "" && strings.HasSuffix(*opts.DecryptInFile, ".aes") {
			*opts.DecryptOutFile = strings.TrimSuffix(filepath.Base(*opts.DecryptInFile), ".aes")
		}
		log.Infof("Decrypting file %q into %q", *opts.DecryptInFile, *opts.DecryptOutFile)
		err = decrypt(*opts.DecryptInFile, *opts.DecryptOutFile, password)
	case "encrypt":
		if *opts.EncryptOutFile == "" {
			*opts.EncryptOutFile = filepath.Base(*opts.EncryptInFile) + ".aes"
		}
		log.Infof("Encrypting file %q into %q", *opts.EncryptInFile, *opts.EncryptOutFile)
		err = encrypt(*opts.EncryptInFile, *opts.EncryptOutFile, password)
	}
	return
}

func encrypt(infile, outfile string, pass [32]byte) error {
	key := pass[:]
	inFile, err := os.Open(infile)
	if err != nil {
		return errors.Wrapf(err, "Cannot open input file %q", infile)
	}
	defer inFile.Close()

	block, err := aes.NewCipher(key)
	if err != nil {
		return errors.Wrapf(err, "Cannot create a new cipher")
	}

	// If the key is unique for each ciphertext, then it's ok to use a zero IV.
	var iv [aes.BlockSize]byte
	stream := cipher.NewOFB(block, iv[:])

	outFile, err := os.OpenFile(outfile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return errors.Wrapf(err, "Cannot create output file %q", outfile)
	}
	defer outFile.Close()

	writer := &cipher.StreamWriter{S: stream, W: outFile}
	// Copy the input file to the output file, encrypting as we go.
	if _, err := io.Copy(writer, inFile); err != nil {
		return errors.Wrapf(err, "Cannot write to output file %q", outfile)
	}
	return nil
}

func decrypt(infile, outfile string, pass [32]byte) error {
	key := pass[:]
	inFile, err := os.Open(infile)
	if err != nil {
		return errors.Wrapf(err, "Cannot open %q for reading", infile)
	}
	defer inFile.Close()

	block, err := aes.NewCipher(key)
	if err != nil {
		return errors.Wrap(err, "Cannot create the cipher")
	}

	// If the key is unique for each ciphertext, then it's ok to use a zero IV.
	var iv [aes.BlockSize]byte
	stream := cipher.NewOFB(block, iv[:])

	outFile, err := os.OpenFile(outfile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return errors.Wrapf(err, "Cannot open %q for writing", outfile)
	}
	defer outFile.Close()

	reader := &cipher.StreamReader{S: stream, R: inFile}
	// Copy the input file to the output file, decrypting as we go.
	if _, err := io.Copy(outFile, reader); err != nil {
		return errors.Wrapf(err, "Cannot write to output file %q", outfile)
	}
	return nil
}
