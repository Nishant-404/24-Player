package gobackend

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/go-flac/flacpicture"
	"github.com/go-flac/flacvorbis"
	"github.com/go-flac/go-flac"
)

type Metadata struct {
	Title       string
	Artist      string
	Album       string
	AlbumArtist string
	Date        string
	TrackNumber int
	TotalTracks int
	DiscNumber  int
	ISRC        string
	Description string
	Lyrics      string
	Genre       string
	Label       string
	Copyright   string
}

func EmbedMetadata(filePath string, metadata Metadata, coverPath string) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	setComment(cmt, "TITLE", metadata.Title)
	setComment(cmt, "ARTIST", metadata.Artist)
	setComment(cmt, "ALBUM", metadata.Album)
	setComment(cmt, "ALBUMARTIST", metadata.AlbumArtist)
	setComment(cmt, "DATE", metadata.Date)

	if metadata.TrackNumber > 0 {
		if metadata.TotalTracks > 0 {
			setComment(cmt, "TRACKNUMBER", fmt.Sprintf("%d/%d", metadata.TrackNumber, metadata.TotalTracks))
		} else {
			setComment(cmt, "TRACKNUMBER", strconv.Itoa(metadata.TrackNumber))
		}
	}

	if metadata.DiscNumber > 0 {
		setComment(cmt, "DISCNUMBER", strconv.Itoa(metadata.DiscNumber))
	}

	if metadata.ISRC != "" {
		setComment(cmt, "ISRC", metadata.ISRC)
	}

	if metadata.Description != "" {
		setComment(cmt, "DESCRIPTION", metadata.Description)
	}

	if metadata.Lyrics != "" {
		setComment(cmt, "LYRICS", metadata.Lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", metadata.Lyrics)
	}

	if metadata.Genre != "" {
		setComment(cmt, "GENRE", metadata.Genre)
	}

	if metadata.Label != "" {
		setComment(cmt, "ORGANIZATION", metadata.Label)
	}

	if metadata.Copyright != "" {
		setComment(cmt, "COPYRIGHT", metadata.Copyright)
	}

	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	if coverPath != "" {
		if fileExists(coverPath) {
			coverData, err := os.ReadFile(coverPath)
			if err != nil {
				fmt.Printf("[Metadata] Warning: Failed to read cover file %s: %v\n", coverPath, err)
			} else {
				for i := len(f.Meta) - 1; i >= 0; i-- {
					if f.Meta[i].Type == flac.Picture {
						f.Meta = append(f.Meta[:i], f.Meta[i+1:]...)
					}
				}

				picture, err := flacpicture.NewFromImageData(
					flacpicture.PictureTypeFrontCover,
					"Front Cover",
					coverData,
					"image/jpeg",
				)
				if err != nil {
					fmt.Printf("[Metadata] Warning: Failed to create picture block: %v\n", err)
				} else {
					picBlock := picture.Marshal()
					f.Meta = append(f.Meta, &picBlock)
					fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
				}
			}
		} else {
			fmt.Printf("[Metadata] Warning: Cover file does not exist: %s\n", coverPath)
		}
	}

	return f.Save(filePath)
}

func EmbedMetadataWithCoverData(filePath string, metadata Metadata, coverData []byte) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	setComment(cmt, "TITLE", metadata.Title)
	setComment(cmt, "ARTIST", metadata.Artist)
	setComment(cmt, "ALBUM", metadata.Album)
	setComment(cmt, "ALBUMARTIST", metadata.AlbumArtist)
	setComment(cmt, "DATE", metadata.Date)

	if metadata.TrackNumber > 0 {
		if metadata.TotalTracks > 0 {
			setComment(cmt, "TRACKNUMBER", fmt.Sprintf("%d/%d", metadata.TrackNumber, metadata.TotalTracks))
		} else {
			setComment(cmt, "TRACKNUMBER", strconv.Itoa(metadata.TrackNumber))
		}
	}

	if metadata.DiscNumber > 0 {
		setComment(cmt, "DISCNUMBER", strconv.Itoa(metadata.DiscNumber))
	}

	if metadata.ISRC != "" {
		setComment(cmt, "ISRC", metadata.ISRC)
	}

	if metadata.Description != "" {
		setComment(cmt, "DESCRIPTION", metadata.Description)
	}

	if metadata.Lyrics != "" {
		setComment(cmt, "LYRICS", metadata.Lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", metadata.Lyrics)
	}

	if metadata.Genre != "" {
		setComment(cmt, "GENRE", metadata.Genre)
	}

	if metadata.Label != "" {
		setComment(cmt, "ORGANIZATION", metadata.Label)
	}

	if metadata.Copyright != "" {
		setComment(cmt, "COPYRIGHT", metadata.Copyright)
	}

	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	if len(coverData) > 0 {
		for i := len(f.Meta) - 1; i >= 0; i-- {
			if f.Meta[i].Type == flac.Picture {
				f.Meta = append(f.Meta[:i], f.Meta[i+1:]...)
			}
		}

		picture, err := flacpicture.NewFromImageData(
			flacpicture.PictureTypeFrontCover,
			"Front Cover",
			coverData,
			"image/jpeg",
		)
		if err != nil {
			fmt.Printf("[Metadata] Warning: Failed to create picture block: %v\n", err)
		} else {
			picBlock := picture.Marshal()
			f.Meta = append(f.Meta, &picBlock)
			fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
		}
	}

	return f.Save(filePath)
}

// ReadMetadata reads metadata from a FLAC file
func ReadMetadata(filePath string) (*Metadata, error) {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	metadata := &Metadata{}

	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}

			metadata.Title = getComment(cmt, "TITLE")
			metadata.Artist = getComment(cmt, "ARTIST")
			metadata.Album = getComment(cmt, "ALBUM")
			metadata.AlbumArtist = getComment(cmt, "ALBUMARTIST")
			metadata.Date = getComment(cmt, "DATE")
			metadata.ISRC = getComment(cmt, "ISRC")
			metadata.Description = getComment(cmt, "DESCRIPTION")

			metadata.Lyrics = getComment(cmt, "LYRICS")
			if metadata.Lyrics == "" {
				metadata.Lyrics = getComment(cmt, "UNSYNCEDLYRICS")
			}

			trackNum := getComment(cmt, "TRACKNUMBER")
			if trackNum != "" {
				fmt.Sscanf(trackNum, "%d", &metadata.TrackNumber)
			}
			if metadata.TrackNumber == 0 {
				trackNum = getComment(cmt, "TRACK")
				if trackNum != "" {
					fmt.Sscanf(trackNum, "%d", &metadata.TrackNumber)
				}
			}

			discNum := getComment(cmt, "DISCNUMBER")
			if discNum != "" {
				fmt.Sscanf(discNum, "%d", &metadata.DiscNumber)
			}
			if metadata.DiscNumber == 0 {
				discNum = getComment(cmt, "DISC")
				if discNum != "" {
					fmt.Sscanf(discNum, "%d", &metadata.DiscNumber)
				}
			}

			if metadata.Date == "" {
				metadata.Date = getComment(cmt, "YEAR")
			}

			break
		}
	}

	return metadata, nil
}

func setComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value string) {
	if value == "" {
		return
	}
	keyUpper := strings.ToUpper(key)
	for i := len(cmt.Comments) - 1; i >= 0; i-- {
		comment := cmt.Comments[i]
		eqIdx := strings.Index(comment, "=")
		if eqIdx > 0 {
			existingKey := strings.ToUpper(comment[:eqIdx])
			if existingKey == keyUpper {
				cmt.Comments = append(cmt.Comments[:i], cmt.Comments[i+1:]...)
			}
		}
	}
	cmt.Comments = append(cmt.Comments, key+"="+value)
}

func getComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) string {
	keyUpper := strings.ToUpper(key) + "="
	for _, comment := range cmt.Comments {
		if len(comment) > len(key) {
			commentUpper := strings.ToUpper(comment[:len(key)+1])
			if commentUpper == keyUpper {
				return comment[len(key)+1:]
			}
		}
	}
	return ""
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func EmbedLyrics(filePath string, lyrics string) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	setComment(cmt, "LYRICS", lyrics)
	setComment(cmt, "UNSYNCEDLYRICS", lyrics)

	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	return f.Save(filePath)
}

func EmbedGenreLabel(filePath string, genre, label string) error {
	if genre == "" && label == "" {
		return nil
	}

	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	if genre != "" {
		setComment(cmt, "GENRE", genre)
	}
	if label != "" {
		setComment(cmt, "ORGANIZATION", label)
	}

	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	return f.Save(filePath)
}

// ExtractLyrics extracts embedded lyrics from a FLAC file
func ExtractLyrics(filePath string) (string, error) {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}

			lyrics, err := cmt.Get("LYRICS")
			if err == nil && len(lyrics) > 0 && lyrics[0] != "" {
				return lyrics[0], nil
			}

			lyrics, err = cmt.Get("UNSYNCEDLYRICS")
			if err == nil && len(lyrics) > 0 && lyrics[0] != "" {
				return lyrics[0], nil
			}
		}
	}

	return "", fmt.Errorf("no lyrics found in file")
}

type AudioQuality struct {
	BitDepth     int   `json:"bit_depth"`
	SampleRate   int   `json:"sample_rate"`
	TotalSamples int64 `json:"total_samples"`
}

func GetAudioQuality(filePath string) (AudioQuality, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	marker := make([]byte, 4)
	if _, err := file.Read(marker); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read marker: %w", err)
	}

	if string(marker) == "fLaC" {
		header := make([]byte, 4)
		if _, err := file.Read(header); err != nil {
			return AudioQuality{}, fmt.Errorf("failed to read header: %w", err)
		}

		blockType := header[0] & 0x7F
		if blockType != 0 {
			return AudioQuality{}, fmt.Errorf("first block is not STREAMINFO")
		}

		streamInfo := make([]byte, 34)
		if _, err := file.Read(streamInfo); err != nil {
			return AudioQuality{}, fmt.Errorf("failed to read STREAMINFO: %w", err)
		}

		sampleRate := (int(streamInfo[10]) << 12) | (int(streamInfo[11]) << 4) | (int(streamInfo[12]) >> 4)

		bitsPerSample := ((int(streamInfo[12]) & 0x01) << 4) | (int(streamInfo[13]) >> 4) + 1

		totalSamples := int64(streamInfo[13]&0x0F)<<32 |
			int64(streamInfo[14])<<24 |
			int64(streamInfo[15])<<16 |
			int64(streamInfo[16])<<8 |
			int64(streamInfo[17])

		return AudioQuality{
			BitDepth:     bitsPerSample,
			SampleRate:   sampleRate,
			TotalSamples: totalSamples,
		}, nil
	}

	file.Seek(0, 0)
	header8 := make([]byte, 8)
	if _, err := file.Read(header8); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read header: %w", err)
	}

	if string(header8[4:8]) == "ftyp" {
		file.Close()
		return GetM4AQuality(filePath)
	}

	return AudioQuality{}, fmt.Errorf("unsupported file format (not FLAC or M4A)")
}

// ========================================
// M4A (MP4/AAC) Metadata Embedding
// ========================================

// EmbedM4AMetadata embeds metadata into an M4A file using iTunes-style atoms
func EmbedM4AMetadata(filePath string, metadata Metadata, coverData []byte) error {
	input, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open M4A file: %w", err)
	}
	defer input.Close()

	info, err := input.Stat()
	if err != nil {
		return fmt.Errorf("failed to stat M4A file: %w", err)
	}
	fileSize := info.Size()

	moovHeader, moovFound, err := findAtomInRange(input, 0, fileSize, "moov", fileSize)
	if err != nil {
		return fmt.Errorf("failed to find moov atom: %w", err)
	}
	if !moovFound {
		return fmt.Errorf("moov atom not found in M4A file")
	}

	moovContentStart := moovHeader.offset + moovHeader.headerSize
	moovContentSize := moovHeader.size - moovHeader.headerSize

	udtaHeader, udtaFound, err := findAtomInRange(input, moovContentStart, moovContentSize, "udta", fileSize)
	if err != nil {
		return fmt.Errorf("failed to locate udta atom: %w", err)
	}

	var metaHeader atomHeader
	metaFound := false
	if udtaFound {
		udtaContentStart := udtaHeader.offset + udtaHeader.headerSize
		udtaContentSize := udtaHeader.size - udtaHeader.headerSize
		metaHeader, metaFound, err = findAtomInRange(input, udtaContentStart, udtaContentSize, "meta", fileSize)
		if err != nil {
			return fmt.Errorf("failed to locate meta atom: %w", err)
		}
	}

	metaAtom := buildMetaAtom(metadata, coverData)
	metaSize := int64(len(metaAtom))

	var delta int64
	var newUdtaSize int64
	switch {
	case udtaFound && metaFound:
		delta = metaSize - metaHeader.size
		newUdtaSize = udtaHeader.size + delta
	case udtaFound && !metaFound:
		delta = metaSize
		newUdtaSize = udtaHeader.size + delta
	case !udtaFound:
		newUdtaSize = int64(8 + len(metaAtom))
		delta = newUdtaSize
	}

	newMoovSize := moovHeader.size + delta
	if moovHeader.headerSize == 8 && newMoovSize > int64(^uint32(0)) {
		return fmt.Errorf("moov atom exceeds 32-bit size after update")
	}
	if udtaFound && udtaHeader.headerSize == 8 && newUdtaSize > int64(^uint32(0)) {
		return fmt.Errorf("udta atom exceeds 32-bit size after update")
	}
	if !udtaFound && newUdtaSize > int64(^uint32(0)) {
		return fmt.Errorf("udta atom exceeds 32-bit size after update")
	}

	tempPath := filePath + ".tmp"
	output, err := os.OpenFile(tempPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	cleanupTemp := true
	defer func() {
		_ = output.Close()
		if cleanupTemp {
			_ = os.Remove(tempPath)
		}
	}()

	switch {
	case udtaFound && metaFound:
		if err := copyRange(output, input, 0, moovHeader.offset); err != nil {
			return err
		}
		if err := writeAtomHeader(output, "moov", newMoovSize, moovHeader.headerSize); err != nil {
			return err
		}
		if err := copyRange(output, input, moovHeader.offset+moovHeader.headerSize, udtaHeader.offset-(moovHeader.offset+moovHeader.headerSize)); err != nil {
			return err
		}
		if err := writeAtomHeader(output, "udta", newUdtaSize, udtaHeader.headerSize); err != nil {
			return err
		}
		if err := copyRange(output, input, udtaHeader.offset+udtaHeader.headerSize, metaHeader.offset-(udtaHeader.offset+udtaHeader.headerSize)); err != nil {
			return err
		}
		if _, err := output.Write(metaAtom); err != nil {
			return fmt.Errorf("failed to write meta atom: %w", err)
		}
		metaEnd := metaHeader.offset + metaHeader.size
		if err := copyRange(output, input, metaEnd, fileSize-metaEnd); err != nil {
			return err
		}
	case udtaFound && !metaFound:
		if err := copyRange(output, input, 0, moovHeader.offset); err != nil {
			return err
		}
		if err := writeAtomHeader(output, "moov", newMoovSize, moovHeader.headerSize); err != nil {
			return err
		}
		if err := copyRange(output, input, moovHeader.offset+moovHeader.headerSize, udtaHeader.offset-(moovHeader.offset+moovHeader.headerSize)); err != nil {
			return err
		}
		if err := writeAtomHeader(output, "udta", newUdtaSize, udtaHeader.headerSize); err != nil {
			return err
		}
		insertPos := udtaHeader.offset + udtaHeader.size
		if err := copyRange(output, input, udtaHeader.offset+udtaHeader.headerSize, insertPos-(udtaHeader.offset+udtaHeader.headerSize)); err != nil {
			return err
		}
		if _, err := output.Write(metaAtom); err != nil {
			return fmt.Errorf("failed to write meta atom: %w", err)
		}
		if err := copyRange(output, input, insertPos, fileSize-insertPos); err != nil {
			return err
		}
	case !udtaFound:
		newUdtaAtom := buildUdtaAtom(metaAtom)
		if err := copyRange(output, input, 0, moovHeader.offset); err != nil {
			return err
		}
		if err := writeAtomHeader(output, "moov", newMoovSize, moovHeader.headerSize); err != nil {
			return err
		}
		moovEnd := moovHeader.offset + moovHeader.size
		if err := copyRange(output, input, moovHeader.offset+moovHeader.headerSize, moovEnd-(moovHeader.offset+moovHeader.headerSize)); err != nil {
			return err
		}
		if _, err := output.Write(newUdtaAtom); err != nil {
			return fmt.Errorf("failed to write udta atom: %w", err)
		}
		if err := copyRange(output, input, moovEnd, fileSize-moovEnd); err != nil {
			return err
		}
	}

	if err := output.Close(); err != nil {
		return fmt.Errorf("failed to close temp file: %w", err)
	}

	_ = input.Close()
	if err := os.Remove(filePath); err != nil {
		return fmt.Errorf("failed to replace original file: %w", err)
	}
	if err := os.Rename(tempPath, filePath); err != nil {
		return fmt.Errorf("failed to move temp file: %w", err)
	}
	cleanupTemp = false

	fmt.Printf("[M4A] Metadata embedded successfully\n")
	return nil
}

func findAtom(data []byte, name string, offset int) int {
	for i := offset; i < len(data)-8; {
		size := int(uint32(data[i])<<24 | uint32(data[i+1])<<16 | uint32(data[i+2])<<8 | uint32(data[i+3]))
		if size < 8 {
			break
		}
		atomName := string(data[i+4 : i+8])
		if atomName == name {
			return i
		}
		i += size
	}
	return -1
}

// buildMetaAtom builds a complete meta atom with ilst containing metadata
func buildMetaAtom(metadata Metadata, coverData []byte) []byte {
	var ilst []byte

	if metadata.Title != "" {
		ilst = append(ilst, buildTextAtom("©nam", metadata.Title)...)
	}

	if metadata.Artist != "" {
		ilst = append(ilst, buildTextAtom("©ART", metadata.Artist)...)
	}

	if metadata.Album != "" {
		ilst = append(ilst, buildTextAtom("©alb", metadata.Album)...)
	}

	if metadata.AlbumArtist != "" {
		ilst = append(ilst, buildTextAtom("aART", metadata.AlbumArtist)...)
	}

	if metadata.Date != "" {
		ilst = append(ilst, buildTextAtom("©day", metadata.Date)...)
	}

	if metadata.TrackNumber > 0 {
		ilst = append(ilst, buildTrackNumberAtom(metadata.TrackNumber, metadata.TotalTracks)...)
	}

	if metadata.DiscNumber > 0 {
		ilst = append(ilst, buildDiscNumberAtom(metadata.DiscNumber, 0)...)
	}

	if metadata.Lyrics != "" {
		ilst = append(ilst, buildTextAtom("©lyr", metadata.Lyrics)...)
	}

	if len(coverData) > 0 {
		ilst = append(ilst, buildCoverAtom(coverData)...)
	}

	ilstSize := 8 + len(ilst)
	ilstAtom := make([]byte, 4)
	ilstAtom[0] = byte(ilstSize >> 24)
	ilstAtom[1] = byte(ilstSize >> 16)
	ilstAtom[2] = byte(ilstSize >> 8)
	ilstAtom[3] = byte(ilstSize)
	ilstAtom = append(ilstAtom, []byte("ilst")...)
	ilstAtom = append(ilstAtom, ilst...)

	hdlr := []byte{
		0, 0, 0, 33, // size = 33
		'h', 'd', 'l', 'r',
		0, 0, 0, 0, // version + flags
		0, 0, 0, 0, // predefined
		'm', 'd', 'i', 'r', // handler type
		'a', 'p', 'p', 'l', // manufacturer
		0, 0, 0, 0, // component flags
		0, 0, 0, 0, // component flags mask
		0, // null terminator
	}

	metaContent := append([]byte{0, 0, 0, 0}, hdlr...) // version + flags + hdlr
	metaContent = append(metaContent, ilstAtom...)

	metaSize := 8 + len(metaContent)
	metaAtom := make([]byte, 4)
	metaAtom[0] = byte(metaSize >> 24)
	metaAtom[1] = byte(metaSize >> 16)
	metaAtom[2] = byte(metaSize >> 8)
	metaAtom[3] = byte(metaSize)
	metaAtom = append(metaAtom, []byte("meta")...)
	metaAtom = append(metaAtom, metaContent...)

	return metaAtom
}

func buildTextAtom(name, value string) []byte {
	valueBytes := []byte(value)

	dataSize := 16 + len(valueBytes)
	dataAtom := make([]byte, 4)
	dataAtom[0] = byte(dataSize >> 24)
	dataAtom[1] = byte(dataSize >> 16)
	dataAtom[2] = byte(dataSize >> 8)
	dataAtom[3] = byte(dataSize)
	dataAtom = append(dataAtom, []byte("data")...)
	dataAtom = append(dataAtom, 0, 0, 0, 1) // type = UTF-8
	dataAtom = append(dataAtom, 0, 0, 0, 0) // locale
	dataAtom = append(dataAtom, valueBytes...)

	atomSize := 8 + len(dataAtom)
	atom := make([]byte, 4)
	atom[0] = byte(atomSize >> 24)
	atom[1] = byte(atomSize >> 16)
	atom[2] = byte(atomSize >> 8)
	atom[3] = byte(atomSize)
	atom = append(atom, []byte(name)...)
	atom = append(atom, dataAtom...)

	return atom
}

// buildTrackNumberAtom builds trkn atom
func buildTrackNumberAtom(track, total int) []byte {
	dataAtom := []byte{
		0, 0, 0, 24, // size
		'd', 'a', 't', 'a',
		0, 0, 0, 0, // type = implicit
		0, 0, 0, 0, // locale
		0, 0, // padding
		byte(track >> 8), byte(track), // track number
		byte(total >> 8), byte(total), // total tracks
		0, 0, // padding
	}

	atomSize := 8 + len(dataAtom)
	atom := make([]byte, 4)
	atom[0] = byte(atomSize >> 24)
	atom[1] = byte(atomSize >> 16)
	atom[2] = byte(atomSize >> 8)
	atom[3] = byte(atomSize)
	atom = append(atom, []byte("trkn")...)
	atom = append(atom, dataAtom...)

	return atom
}

func buildDiscNumberAtom(disc, total int) []byte {
	dataAtom := []byte{
		0, 0, 0, 22, // size
		'd', 'a', 't', 'a',
		0, 0, 0, 0, // type = implicit
		0, 0, 0, 0, // locale
		0, 0, // padding
		byte(disc >> 8), byte(disc), // disc number
		byte(total >> 8), byte(total), // total discs
	}

	atomSize := 8 + len(dataAtom)
	atom := make([]byte, 4)
	atom[0] = byte(atomSize >> 24)
	atom[1] = byte(atomSize >> 16)
	atom[2] = byte(atomSize >> 8)
	atom[3] = byte(atomSize)
	atom = append(atom, []byte("disk")...)
	atom = append(atom, dataAtom...)

	return atom
}

// buildCoverAtom builds covr atom with image data
func buildCoverAtom(coverData []byte) []byte {
	imageType := byte(13)
	if len(coverData) > 8 && coverData[0] == 0x89 && coverData[1] == 'P' && coverData[2] == 'N' && coverData[3] == 'G' {
		imageType = 14
	}

	dataSize := 16 + len(coverData)
	dataAtom := make([]byte, 4)
	dataAtom[0] = byte(dataSize >> 24)
	dataAtom[1] = byte(dataSize >> 16)
	dataAtom[2] = byte(dataSize >> 8)
	dataAtom[3] = byte(dataSize)
	dataAtom = append(dataAtom, []byte("data")...)
	dataAtom = append(dataAtom, 0, 0, 0, imageType)
	dataAtom = append(dataAtom, 0, 0, 0, 0)
	dataAtom = append(dataAtom, coverData...)

	atomSize := 8 + len(dataAtom)
	atom := make([]byte, 4)
	atom[0] = byte(atomSize >> 24)
	atom[1] = byte(atomSize >> 16)
	atom[2] = byte(atomSize >> 8)
	atom[3] = byte(atomSize)
	atom = append(atom, []byte("covr")...)
	atom = append(atom, dataAtom...)

	return atom
}

func GetM4AQuality(filePath string) (AudioQuality, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to open M4A file: %w", err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to stat M4A file: %w", err)
	}
	fileSize := info.Size()

	moovHeader, moovFound, err := findAtomInRange(f, 0, fileSize, "moov", fileSize)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to find moov atom: %w", err)
	}
	if !moovFound {
		return AudioQuality{}, fmt.Errorf("moov atom not found")
	}

	moovStart := moovHeader.offset
	moovEnd := moovHeader.offset + moovHeader.size

	sampleOffset, atomType, err := findAudioSampleEntry(f, moovStart, moovEnd, fileSize)
	if err != nil {
		return AudioQuality{}, err
	}

	buf := make([]byte, 24)
	if _, err := f.ReadAt(buf, sampleOffset); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read audio sample entry: %w", err)
	}

	sampleRate := int(buf[22])<<8 | int(buf[23])
	bitDepth := 16
	if atomType == "alac" {
		bitDepth = 24
	}

	return AudioQuality{BitDepth: bitDepth, SampleRate: sampleRate}, nil
}

type atomHeader struct {
	offset     int64
	size       int64
	headerSize int64
	typ        string
}

func readAtomHeaderAt(f *os.File, offset, fileSize int64) (atomHeader, error) {
	if offset+8 > fileSize {
		return atomHeader{}, io.ErrUnexpectedEOF
	}

	headerBuf := make([]byte, 8)
	if _, err := f.ReadAt(headerBuf, offset); err != nil {
		return atomHeader{}, err
	}

	size32 := binary.BigEndian.Uint32(headerBuf[0:4])
	typ := string(headerBuf[4:8])

	if size32 == 1 {
		if offset+16 > fileSize {
			return atomHeader{}, io.ErrUnexpectedEOF
		}
		extBuf := make([]byte, 8)
		if _, err := f.ReadAt(extBuf, offset+8); err != nil {
			return atomHeader{}, err
		}
		size64 := binary.BigEndian.Uint64(extBuf)
		return atomHeader{offset: offset, size: int64(size64), headerSize: 16, typ: typ}, nil
	}

	return atomHeader{offset: offset, size: int64(size32), headerSize: 8, typ: typ}, nil
}

func findAtomInRange(f *os.File, start, size int64, target string, fileSize int64) (atomHeader, bool, error) {
	if size <= 0 {
		return atomHeader{}, false, nil
	}

	end := start + size
	pos := start

	for pos+8 <= end {
		header, err := readAtomHeaderAt(f, pos, fileSize)
		if err != nil {
			return atomHeader{}, false, err
		}

		atomSize := header.size
		if atomSize == 0 {
			atomSize = end - pos
		}

		if atomSize < header.headerSize {
			return atomHeader{}, false, fmt.Errorf("invalid atom size for %s", header.typ)
		}

		header.size = atomSize
		if header.typ == target {
			return header, true, nil
		}

		pos += atomSize
	}

	return atomHeader{}, false, nil
}

func writeAtomHeader(w io.Writer, typ string, size int64, headerSize int64) error {
	if len(typ) != 4 {
		return fmt.Errorf("invalid atom type: %s", typ)
	}

	if headerSize == 16 {
		header := make([]byte, 16)
		binary.BigEndian.PutUint32(header[0:4], 1)
		copy(header[4:8], []byte(typ))
		binary.BigEndian.PutUint64(header[8:16], uint64(size))
		_, err := w.Write(header)
		return err
	}

	if size > int64(^uint32(0)) {
		return fmt.Errorf("atom size exceeds 32-bit for %s", typ)
	}

	header := make([]byte, 8)
	binary.BigEndian.PutUint32(header[0:4], uint32(size))
	copy(header[4:8], []byte(typ))
	_, err := w.Write(header)
	return err
}

func copyRange(dst io.Writer, src *os.File, offset, length int64) error {
	if length <= 0 {
		return nil
	}
	if _, err := src.Seek(offset, io.SeekStart); err != nil {
		return fmt.Errorf("failed to seek source: %w", err)
	}
	if _, err := io.CopyN(dst, src, length); err != nil {
		return fmt.Errorf("failed to copy data: %w", err)
	}
	return nil
}

func buildUdtaAtom(metaAtom []byte) []byte {
	size := 8 + len(metaAtom)
	header := make([]byte, 8)
	binary.BigEndian.PutUint32(header[0:4], uint32(size))
	copy(header[4:8], []byte("udta"))
	return append(header, metaAtom...)
}

func findAudioSampleEntry(f *os.File, start, end, fileSize int64) (int64, string, error) {
	const chunkSize = 64 * 1024
	patternMP4A := []byte("mp4a")
	patternALAC := []byte("alac")

	var tail []byte
	readPos := start

	for readPos < end {
		toRead := end - readPos
		if toRead > chunkSize {
			toRead = chunkSize
		}

		buf := make([]byte, toRead)
		n, err := f.ReadAt(buf, readPos)
		if err != nil && err != io.EOF {
			return 0, "", fmt.Errorf("failed to read M4A atom data: %w", err)
		}
		if n == 0 {
			break
		}

		data := append(tail, buf[:n]...)
		mp4aIdx := bytes.Index(data, patternMP4A)
		alacIdx := bytes.Index(data, patternALAC)

		bestIdx := -1
		bestType := ""
		switch {
		case mp4aIdx >= 0 && alacIdx >= 0:
			if mp4aIdx <= alacIdx {
				bestIdx = mp4aIdx
				bestType = "mp4a"
			} else {
				bestIdx = alacIdx
				bestType = "alac"
			}
		case mp4aIdx >= 0:
			bestIdx = mp4aIdx
			bestType = "mp4a"
		case alacIdx >= 0:
			bestIdx = alacIdx
			bestType = "alac"
		}

		if bestIdx >= 0 {
			absolute := readPos - int64(len(tail)) + int64(bestIdx)
			if absolute+24 > fileSize {
				return 0, "", fmt.Errorf("audio info not found in M4A file")
			}
			return absolute, bestType, nil
		}

		if len(data) >= 3 {
			tail = append([]byte{}, data[len(data)-3:]...)
		} else {
			tail = append([]byte{}, data...)
		}

		readPos += int64(n)
	}

	return 0, "", fmt.Errorf("audio info not found in M4A file")
}
