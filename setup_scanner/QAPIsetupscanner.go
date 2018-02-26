package main

import (
	"bufio"
	"encoding/base64"
	"encoding/xml"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
)

func Get_Credential_Hash(User string, Password string) string {

	return base64.StdEncoding.EncodeToString([]byte(User + ":" + Password))
}

func Usage() {
	fmt.Println("usage: QAPIsetupscanner [-user -password -APIURL -filename]")
	fmt.Println("    -filename is optional, if not used, default will be scannernames.txt in local directory.  This file must have scanner names of 1 per line")
	fmt.Println("Make sure the APIURL includes the https:// at the beginning or you will get run time error ")
}

func Get_Command_Line_Args() (string, string, string, string) {
	/* Get cmd line paramters */
	UserPtr := flag.String("user", "BOGUS", "Qualys Account User Name")
	PasswordPtr := flag.String("password", "BOGUS", "Qualys Account password")
	APIURLPtr := flag.String("APIURL", "https://qualysapi.qualys.com/", "Qualys API endpoint")
	CSVName := flag.String("filename", "scannernames.txt", "Scanner Names File")
	flag.Parse()
	return *UserPtr, *PasswordPtr, *APIURLPtr, *CSVName
}

func Create_Scanner(EncodedCred string, APIURL string, ScannerName string) (string, string, string) {

	type VirtualScanner struct {
		DATE  string `xml:"DATETIME"`
		APPLS struct {
			ID       string `xml:"ID"`
			NAME     string `xml:"FRIENDLY_NAME"`
			PERSCODE string `xml:"ACTIVATION_CODE"`
			RL       int    `xml:"REMAINING_QVSA_LICENSES"`
		} `xml:"RESPONSE>APPLIANCE"`
	}

	/* Build the call, add the parameters, add the headers with auth, etc and make the call */
	resource := "/api/2.0/fo/appliance/"
	data := url.Values{}
	data.Set("action", "create")
	data.Add("name", ScannerName)
	data.Add("polling_interval", "180")
	u, _ := url.ParseRequestURI(APIURL)
	u.Path = resource
	u.RawQuery = data.Encode()
	urlStr := fmt.Sprintf("%v", u)
	fmt.Println("Calling API:", urlStr)
	req, _ := http.NewRequest("POST", urlStr, strings.NewReader(data.Encode()))
	req.Header.Add("X-requested-With", "GOLANG")
	req.Header.Add("authorization", "Basic "+EncodedCred)
	req.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	response, _ := http.DefaultClient.Do(req)
	defer response.Body.Close()

	respStatus := response.Status
	fmt.Println(respStatus)
	defer response.Body.Close()

	body, _ := ioutil.ReadAll(response.Body)
	var VS VirtualScanner
	xml.Unmarshal(body, &VS)
	if respStatus == "200 OK" {
		f, err := os.OpenFile("XMLOUTPUT.xml", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			log.Fatal(err)
		}
		if _, err := f.Write(body); err != nil {
			log.Fatal(err)
		}
		if err := f.Close(); err != nil {
			log.Fatal(err)
		}
		/* fmt.Println(VS.APPLS.ID, ",", VS.APPLS.NAME, ",", VS.APPLS.PERSCODE) */
		return VS.APPLS.ID, VS.APPLS.NAME, VS.APPLS.PERSCODE
	} else {
		return "FAILED"
	}
}

func main() {
	User, Password, APIURL, CSVFileName := Get_Command_Line_Args()
	/* fmt.Println("user", User)
	fmt.Println("password", Password)
	fmt.Println("APIURL", APIURL)
	fmt.Println("FileName", CSVFileName) */
	EncodedCred := Get_Credential_Hash(User, Password)
	/* Opent the input file for reading */
	file, err := os.Open(CSVFileName)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	/* open the output file for writing */
	outfile, err := os.Create("./activationcodes.csv")
	if err != nil {
		panic(err)
	}
	defer outfile.Close()

	/* main loop of work - get a line from input file and process it */
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		/* fmt.Println(scanner.Text()) */
		ScannerName := scanner.Text()
		ID, NAME, PersCode := Create_Scanner(EncodedCred, APIURL, ScannerName)
		outfile.WriteString(ID + ",")
		outfile.WriteString(NAME + ",")
		outfile.WriteString(PERSCODE + "\n")
		/* fmt.Println(ScannerName, ",", PersCode) */
	}
	outfile.Sync()
	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}
}
