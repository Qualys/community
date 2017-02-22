package main

import (
	"encoding/base64"
	"encoding/xml"
	"flag"
	"fmt"
	"io/ioutil"
	"net/http"
)

func Get_Credential_Hash(User string, Password string) string {

	return base64.StdEncoding.EncodeToString([]byte(User + ":" + Password))
}

func Get_Command_Line_Args() (string, string, string) {
	/* Get cmd line paramters */
	UserPtr := flag.String("User", "BOGUS", "Qualys Account User Name")
	PasswordPtr := flag.String("Password", "BOGUS", "Qualys Account password")
	APIURLPtr := flag.String("API URL", "https://qualysapi.qualys.com/", "Qualys API endpoint")
	flag.Parse()
	return *UserPtr, *PasswordPtr, *APIURLPtr
}

func QAPI_Hostasset_Count() int {

	type Hostasset_Count struct {
		ResponseCode string `xml:"responseCode"`
		Count        int    `xml:"count"`
	}
	User, Password, APIURL := Get_Command_Line_Args()
	encodedcred := Get_Credential_Hash(User, Password)

	url := APIURL + "qps/rest/2.0/count/am/hostasset/"
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Add("X-requested-with", "GOLANG")
	req.Header.Add("authorization", "Basic "+encodedcred)
	/* req.Header.Add() */
	res, _ := http.DefaultClient.Do(req)
	defer res.Body.Close()
	body, _ := ioutil.ReadAll(res.Body)
	/* fmt.Println(res)
	fmt.Println(string(body)) */
	var c Hostasset_Count
	xml.Unmarshal(body, &c)
	if c.ResponseCode == "SUCCESS" {
		return c.Count
	} else {
		return -1
	}
}

func main() {

	var numassets int
	numassets = QAPI_Hostasset_Count()
	if numassets >= 0 {
		fmt.Println("Numnber of Assets:", numassets)
	}
}
