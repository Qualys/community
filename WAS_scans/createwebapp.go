package main

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"encoding/csv"
	//	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
)

func Get_Credential_Hash(User string, Password string) string {

	return base64.StdEncoding.EncodeToString([]byte(User + ":" + Password))
}
func Create_Unique_ID(HostID string, AssetID string, UUID string) string {

	return base64.StdEncoding.EncodeToString([]byte(HostID + ":" + AssetID + ":" + UUID))
}

func Usage() {
	fmt.Println("usage: createwebapps [-user -password -APIURL -filename]")
	fmt.Println("    -filename is optional, if not used, default will be webappnames.txt in local directory.  This file must have URL and  names of 1 per line separated by comma")
	fmt.Println("Make sure the APIURL includes the https:// at the beginning or you will get run time error ")
}

func Get_Command_Line_Args() (string, string, string, string) {
	/* Get cmd line paramters */
	UserPtr := flag.String("user", "", "Qualys Account User Name")
	PasswordPtr := flag.String("password", "", "Qualys Account password")
	APIURLPtr := flag.String("APIURL", "https://qualysapi.qualys.com/", "Qualys API endpoint")
	CSVName := flag.String("filename", "webapps.csv", "WebApp Names File")
	flag.Parse()
	return *UserPtr, *PasswordPtr, *APIURLPtr, *CSVName
}

func Create_WebApp(EncodedCred string, APIURL string, WASName string, WASURL string) string {

	resource := "qps/rest/3.0/create/was/webapp"
	SRXML := "<ServiceRequest><data><WebApp><name>" + WASName + "</name><url>" + WASURL + "</url></WebApp></data></ServiceRequest>"
	fmt.Println(APIURL + resource + ":" + SRXML)
	//client := &http.Client{}

	req, _ := http.NewRequest("POST", APIURL+resource, bytes.NewBuffer([]byte(SRXML)))
	req.Header.Add("X-requested-With", "GOLANG")
	req.Header.Add("authorization", "Basic "+EncodedCred)
	req.Header.Add("Content-Type", "text/xml")
	response, _ := http.DefaultClient.Do(req)

	respStatus := response.Status
	fmt.Println(respStatus)
	defer response.Body.Close()

	body, _ := ioutil.ReadAll(response.Body)

	//XMLRET := xml.Unmarshal(body)
	if respStatus == "200 OK" {
		f, err := os.OpenFile("webapps_XMLOUTPUT.xml", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			log.Fatal(err)
		}
		if _, err := f.Write(body); err != nil {
			log.Fatal(err)
		}
		if err := f.Close(); err != nil {
			log.Fatal(err)
		}
	} else {
		fmt.Println(response, body)
		return "FAILED"

	}
	return "OK"
}

func main() {
	User, Password, APIURL, CSVFileName := Get_Command_Line_Args()
	EncodedCred := Get_Credential_Hash(User, Password)

	/* Open the input file for reading */
	file, err := os.Open(CSVFileName)
	if err != nil {
		log.Fatal(err)
		return
	}
	defer file.Close()
	/* main loop of work - get a line from input file and process it */
	reader := csv.NewReader(bufio.NewReader(file))
	for {
		line, error := reader.Read()
		if error == io.EOF {
			break
		} else if error != nil {
			log.Fatal(error)
		}
		fmt.Println("APIURL: " + APIURL)
		fmt.Println("WebAppName: " + line[0])
		fmt.Println("WebAppURL: " + line[1])
		CallStatus := Create_WebApp(EncodedCred, APIURL, line[0], line[1])
		fmt.Println(CallStatus)
		//if CallStatus == "FAILED" {
		//	break
		//}
	}
}
