// This program is copyright 2018-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

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
	"golang.org/x/crypto/hkdf"
)

var (
	// hkdfInfo used as the context info for HKDF.
	hkdfInfo = []byte("Percona Toolkit")

	// salt is a random 256-byte array used as a salt for HKDF.
	salt = [256]byte{
		0x33, 0xc5, 0xc5, 0x5f, 0x3e, 0x81, 0xf6, 0x8d, 0x51, 0xd8, 0x18, 0xb9, 0xb7, 0x09, 0x70, 0x51,
		0xc3, 0x60, 0x66, 0xef, 0xd4, 0x97, 0x2e, 0xdf, 0x11, 0x59, 0x34, 0x94, 0x47, 0xab, 0xd4, 0x44,
		0xac, 0x2e, 0x89, 0x81, 0x85, 0xd5, 0x83, 0xbd, 0x2d, 0xb5, 0x43, 0xdd, 0xd7, 0x6c, 0x1b, 0xa7,
		0x6d, 0x8f, 0xb7, 0x84, 0x33, 0x1a, 0x5e, 0x31, 0x76, 0x4b, 0x5d, 0x3b, 0x98, 0x38, 0xe3, 0x93,
		0x28, 0xcc, 0x91, 0x30, 0x37, 0xb6, 0x06, 0xd2, 0xab, 0xdc, 0x9a, 0x14, 0xab, 0xb7, 0xd2, 0x90,
		0xd6, 0x1f, 0x1c, 0xc1, 0x74, 0x2c, 0xc2, 0x08, 0x27, 0x68, 0x7a, 0xdd, 0xef, 0x6e, 0xb9, 0x59,
		0xb0, 0x2f, 0x76, 0x36, 0xba, 0xd8, 0x55, 0x22, 0xba, 0x95, 0xd6, 0xfa, 0xa1, 0x69, 0xab, 0x95,
		0x94, 0x1f, 0x61, 0x7f, 0x56, 0x34, 0xaa, 0x17, 0x78, 0xf8, 0xbb, 0xa0, 0x4e, 0x61, 0xad, 0xee,
		0x51, 0x1c, 0x42, 0xa7, 0x07, 0x44, 0xd5, 0xa6, 0x16, 0x72, 0x1b, 0x05, 0x4e, 0xd4, 0xbf, 0x32,
		0x7d, 0xec, 0x8d, 0x4b, 0x19, 0xd2, 0x32, 0x50, 0x3d, 0x1f, 0x2a, 0x51, 0xc9, 0x62, 0x22, 0x75,
		0xb5, 0xde, 0x0d, 0x58, 0x2b, 0x3a, 0xf8, 0x0e, 0xfc, 0x43, 0x07, 0xc3, 0x60, 0x65, 0x83, 0x3d,
		0xa9, 0x84, 0x02, 0x3a, 0x13, 0x85, 0x3e, 0x8d, 0x87, 0x04, 0xee, 0x58, 0x8d, 0x9a, 0xbc, 0xc0,
		0xec, 0xdd, 0x92, 0xf3, 0x96, 0x03, 0x86, 0xbe, 0x51, 0xb8, 0x96, 0xd5, 0x38, 0xed, 0x03, 0x7b,
		0x18, 0x77, 0x26, 0xaf, 0x15, 0x94, 0x60, 0x25, 0x1b, 0x3f, 0x57, 0xa7, 0xe4, 0xe6, 0x63, 0xf8,
		0xe2, 0xca, 0x15, 0x3d, 0xa3, 0xee, 0xcb, 0xef, 0xb3, 0x23, 0x41, 0x54, 0xd4, 0xaa, 0x93, 0xb4,
		0x48, 0xd3, 0x97, 0x7c, 0x39, 0x5e, 0x1d, 0x05, 0x93, 0x34, 0x70, 0xdf, 0xd6, 0xf0, 0x30, 0xc7,
	}
)

// deriveKey derives a cryptographically strong key from password.
func deriveKey(password string) ([]byte, error) {
	hkdf := hkdf.New(sha256.New, []byte(password), salt[:], hkdfInfo)
	key := make([]byte, 32)
	if _, err := io.ReadFull(hkdf, key); err != nil {
		return nil, errors.Wrap(err, "Cannot derive key from password")
	}

	return key, nil
}

func encryptorCmd(opts *cliOptions) (err error) {
	key, err := deriveKey(*opts.EncryptPassword)
	if err != nil {
		return errors.WithStack(err)
	}

	switch opts.Command {
	case "decrypt":
		if *opts.DecryptOutFile == "" && strings.HasSuffix(*opts.DecryptInFile, ".aes") {
			*opts.DecryptOutFile = strings.TrimSuffix(filepath.Base(*opts.DecryptInFile), ".aes")
		}
		log.Infof("Decrypting file %q into %q", *opts.DecryptInFile, *opts.DecryptOutFile)
		err = decrypt(*opts.DecryptInFile, *opts.DecryptOutFile, key)
	case "encrypt":
		if *opts.EncryptOutFile == "" {
			*opts.EncryptOutFile = filepath.Base(*opts.EncryptInFile) + ".aes"
		}
		log.Infof("Encrypting file %q into %q", *opts.EncryptInFile, *opts.EncryptOutFile)
		err = encrypt(*opts.EncryptInFile, *opts.EncryptOutFile, key)
	}
	return
}

func encrypt(infile, outfile string, key []byte) error {
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

	outFile, err := os.OpenFile(outfile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
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

func decrypt(infile, outfile string, key []byte) error {
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

	outFile, err := os.OpenFile(outfile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
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
