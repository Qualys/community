Imports System.IO
Imports System.Net
Imports System.Collections.Generic
Imports System.Xml
Imports System.Xml.Linq
Imports System.Linq
Imports System.Text
Imports RestSharp
 
 
Public Class Form1
 
    Public client = New RestClient("https://qualysapi.qualys.com")
    Public endpoint As String = Nothing
    Public request As RestRequest = Nothing
    Public request_post As RestRequest = Nothing
    Public response As IRestResponse = Nothing
    Public xml_text As String = Nothing
 
    Private Sub Form1_Load(sender As System.Object, e As System.EventArgs) Handles MyBase.Load
 
        Me.Show()
 
    End Sub
 
    Private Sub cmdTestAPICall_Click(sender As System.Object, e As System.EventArgs) Handles cmdTestAPICall.Click
        Dim API_Call As Integer = 0
        API_Call = My.Settings.current_API_REQ
 
        Select Case API_Call
            Case 1
                Call Version1_Req() 'Version 1 API call - Edit Tickets
            Case 2
                Call Version2_Req() 'Version 2 API call - Edit Tickets
            Case 3
                Call Compliance_Download() 'Version 2 API call - Compliance Download Example
            Case 4
                Call KB_Download_Ver2() 'Version 2 API call - KnowledgeBase Example
            Case 5
                Call Version2_DetectionScanReq() 'Version 2 API call - Detection Data example with Background Worker
        End Select
 
    End Sub
 
    Private Sub Version1_Req() 'Edit Tickets
 
        lstWebMsgs.Items.Add("Process API Request. Please Wait...")
        Me.Refresh()
 
        'Set up REST client to connect to US Platform 1.
        Dim APITickets As String = "4612,4623" 'build from a SQL SP call
 
        'Set up credentials. Use the method you prefer to get credentials
        client.Authenticator = New HttpBasicAuthenticator("*****", "*****")
 
        'GET request' See QualysGuard version.'
        request = New RestRequest("msp/about.php")
 
        response = client.Execute(request) ' Response contains the XML file.
        lstWebMsgs.Items.Add(response.Content.ToString)
 
        'Get request. Close tickets  This is what you are sending : 'Url = "https://qualysapi.qualys.com/msp/ticket_edit.php?ticket_numbers=" & APITickets & "&change_state=RESOLVED&add_comment=Cleanup_process_host_not_scanned_in_past_60_days"
        endpoint = [String].Format("msp/ticket_edit.php?{0}={1}", "ticket_numbers", APITickets & "&change_state=RESOLVED&add_comment=Cleanup_process_host_not_scanned_in_past_60_days")
        request_post = New RestRequest(endpoint, Method.GET)
 
        response = client.Execute(request_post)
 
        'Let's see where we are on our API limit. Do we need to throttle our script?
        For Each header In response.Headers
            lstWebMsgs.Items.Add(header.ToString)
        Next
 
        'Print scan results.
        lstWebMsgs.Items.Add(response.Content.ToString)
        Me.Refresh()
 
        xml_text = response.Content
 
        Try
            Dim xdoc As XDocument = XDocument.Parse(xml_text)
            xdoc.Save(Application.StartupPath & "\" & "XML_Edit_Tickets_V1.xml")
        Catch ex As Exception
            lstWebMsgs.Items.Add("Process Error: " & ex.Message)
            Me.Refresh()
            Return
        End Try
 
        lstWebMsgs.Items.Add("Ticket Editing Process Complete")
 
    End Sub
 
    Private Sub Version2_Req() 'Edit Tickets
 
        lstWebMsgs.Items.Add("Process API Request. Please Wait...")
        Me.Refresh()
 
        ' Set up REST client to connect to US Platform 1.
        'Set up credentials.
        client.Authenticator = New HttpBasicAuthenticator("*****", "*****")
 
        request = New RestRequest("msp/ticket_edit.php", Method.POST)
 
        'Add header, reqiured for v2 API.
        request.AddHeader("X-Requested-With", "RestSharp")
 
        'request.AddParameter("action", "list")
        request.AddParameter("ticket_numbers", "4612,4623")
        request.AddParameter("change_state", "RESOLVED")
        request.AddParameter("add_comment", "Cleanup_process_host_not_scanned_in_past_60_days")
 
        response = client.Execute(request)
 
        'Let's see where we are on our API limit. Do we need to throttle our script?
        For Each header In response.Headers
            lstWebMsgs.Items.Add(header.ToString)
        Next
 
        xml_text = response.Content
 
        Try
            Dim xdoc As XDocument = XDocument.Parse(xml_text)
            xdoc.Save(Application.StartupPath & "\" & "XML_Edit_Tickets_V2.xml")
        Catch ex As Exception
            lstWebMsgs.Items.Add("Process Error: " & ex.Message)
            Return
        End Try
       
        lstWebMsgs.Items.Add("Ticket Editing Process Complete")
 
    End Sub
 
    Public Sub Compliance_Download() 'Compliance Information Download
 
        lstWebMsgs.Items.Add("Process API Request. Please Wait...")
        Me.Refresh()
 
        'https://<qualysapi.qualys.com>/api/2.0/fo/compliance/posture/info
        ' Set up REST client to connect to US Platform 1.
 
        'Set up credentials.
        client.Authenticator = New HttpBasicAuthenticator("*****", "*****")
 
 
        'v2 GET request. There are 3 portions to a Compliance Download.  This is an example of each but I'm only using one.
 
        'request = New RestRequest("api/2.0/fo/compliance/posture/info/", Method.[GET])
        'request = New RestRequest("/api/2.0/fo/compliance/control/", Method.[GET])
        request = New RestRequest("/api/2.0/fo/compliance/policy/", Method.[GET])
 
        'Add header, reqiured for v2 API.
        request.AddHeader("X-Requested-With", "RestSharp")
        request.AddParameter("action", "list")
        request.AddParameter("details", "All") 'details={Basic|All|None|Light only with posture call} If omitted Basic is used by default
 
        'request.AddParameter("policy_id", "87568") 'used with Posture call
        'request.AddParameter("ids", "87568") 'can be used with Policy call not mandatory
        'request.AddParameter("truncation_limit", "0") 'return all records for Detection data and Compliance Posture info
 
        lstWebMsgs.Items.Add("Getting Compliance Data...Please Wait...")
        Me.Refresh()
 
        response = client.Execute(request)
 
        'Let's see where we are on our API limit. Do we need to throttle our script?
        For Each header In response.Headers
           lstWebMsgs.Items.Add(header.ToString)
        Next
 
        xml_text = response.Content
 
        Try
            Dim xdoc As XDocument = XDocument.Parse(xml_text)
            xdoc.Save(Application.StartupPath & "\" & "XML_Compliance_Policy_List.xml")
        Catch ex As Exception
            lstWebMsgs.Items.Add("Process Error: " & ex.Message)
            Return
        End Try
       
        lstWebMsgs.Items.Add("Compliance Data Complete")
 
    End Sub
 
    Public Sub KB_Download_Ver2()
 
        lstWebMsgs.Items.Add("Process API Request. Please Wait...")
        Me.Refresh()
 
        'https://qualysapi.qualys.com/api/2.0/fo/knowledge_base/vuln/?action=list&details=All&last_modified_after=YYYY-MM-DD
        ' Set up REST client to connect to US Platform 1.
        'Set up credentials.
        client.Authenticator = New HttpBasicAuthenticator("*****", "*****")
        'v2 GET request.'
        request = New RestRequest("api/2.0/fo/knowledge_base/vuln/", Method.[GET])
 
        'Add header, reqiured for v2 API.
        request.AddHeader("X-Requested-With", "RestSharp")
        request.AddParameter("action", "list")
        request.AddParameter("details", "All")
        'request.AddParameter("last_modified_after", "2014-01-01")  'Use this for differential updates
 
        response = client.Execute(request)
 
        'Let's see where we are on our API limit. Do we need to throttle our script?
        For Each header In response.Headers
            lstWebMsgs.Items.Add(header.ToString)
        Next
 
        xml_text = response.Content
 
        Try
            Dim xdoc As XDocument = XDocument.Parse(xml_text)
            xdoc.Save(Application.StartupPath & "\" & "XMLKnowledgeBase_ver2b.xml")
        Catch ex As Exception
            lstWebMsgs.Items.Add("Process Error: " & ex.Message)
            Return
        End Try
 
        lstWebMsgs.Items.Add("KnowledgeBase Processing Complete.")
 
    End Sub
 
    'Qualys Detection API calls (Uses Version 2)
    Private Sub Version2_DetectionScanReq()
 
        'Get credentials in which ever way you are familiar
        'Set up credentials.
        client.Authenticator = New HttpBasicAuthenticator("*****", "*****")
 
        lstWebMsgs.Items.Add("Starting Detection Data Download...Please Wait...")
        Me.Refresh()
 
        If Not bgwDetectionData.IsBusy Then
            bgwDetectionData.RunWorkerAsync(client.authenticator)
        End If
 
    End Sub
 
    Private Sub bgwDetectionData_DoWork(sender As System.Object, e As System.ComponentModel.DoWorkEventArgs) Handles bgwDetectionData.DoWork
 
        'v2 GET request.' Print out differential scan results.
        '"https://qualysapi.qualys.com/api/2.0/fo/asset/host/vm/detection/?action=list&vm_scan_since=2012-01-01"
 
        ' Set up REST client to connect to US Platform 1.
        request = New RestRequest("api/2.0/fo/asset/host/vm/detection/", Method.[GET])
 
        'Add header, reqiured for v2 API.
        request.AddHeader("X-Requested-With", "RestSharp")
        request.AddParameter("action", "list")
        request.AddParameter("vm_scan_since", "2014-05-20") 'How far to go back by last scan date
        request.AddParameter("truncation_limit", "0") 'return all records or use an integer between 1 and 20,000
        request.AddParameter("status", "New") '"New,Active,Fixed,Re-Opened") 'Show selected vulnerabilities, currently only showing New
        request.AddParameter("show_igs", "1") 'Show Ports
        'request.AddParameter("qids", "?,?") 'QIDs
        'request.AddParameter("ag_titles", "PCI+Hosts") 'Asset Group
        'request.AddParameter("include_search_list_titles", "PCI+Vulns") 'Search lists called PCI Vulns
 
        response = client.Execute(request)
 
        'Let's see where we are on our API limit. Do we need to throttle our script?
        Dim ResponseMSG As String = Nothing
 
        For Each header In response.Headers
            ResponseMSG = header.ToString
            bgwDetectionData.ReportProgress(1, ResponseMSG)
        Next
 
        xml_text = response.Content
 
        Dim xdoc As XDocument = Nothing
 
        Try
            xdoc = XDocument.Parse(xml_text, LoadOptions.PreserveWhitespace)
            xdoc.Save(Application.StartupPath & "\" & "XMLDetection_SCAN_Result_all_results.xml")
        Catch ex As Exception
            bgwDetectionData.ReportProgress("Error Parsing XML : " & ex.Message)
            Dim sw As IO.StreamWriter = New IO.StreamWriter(Application.StartupPath & "\" & "XMLDetection_SCAN_Result_all_results_msg.xml", False)
            For Each line As String In xml_text
                sw.Write(line)
            Next
            sw.Close()
        Finally
         
        End Try
 
    End Sub
 
    Private Sub bgwDetectionData_ProgressChanged(sender As Object, e As System.ComponentModel.ProgressChangedEventArgs) Handles bgwDetectionData.ProgressChanged
        Dim MSG As String = e.UserState
        lstWebMsgs.Items.Add(MSG)
        Me.Refresh()
 
    End Sub
 
   Private Sub bgwDetectionData_RunWorkerCompleted(sender As Object, e As System.ComponentModel.RunWorkerCompletedEventArgs) Handles bgwDetectionData.RunWorkerCompleted
        lstWebMsgs.Items.Add("Detection Data Process Complete")
    End Sub
 
    Private Sub rbAPI_Version1_Edit_Tickets_Call_CheckedChanged(sender As System.Object, e As System.EventArgs) Handles rbAPI_Version1_Edit_Tickets_Call.CheckedChanged
        My.Settings.current_API_REQ = 1
    End Sub
 
    Private Sub rbAPI_Version2_Edit_Tickets_Call_CheckedChanged(sender As System.Object, e As System.EventArgs) Handles rbAPI_Version2_Edit_Tickets_Call.CheckedChanged
        My.Settings.current_API_REQ = 2
    End Sub
 
    Private Sub rbAPI_Version2_Compliance_Call_CheckedChanged(sender As System.Object, e As System.EventArgs) Handles rbAPI_Version2_Compliance_Call.CheckedChanged
        My.Settings.current_API_REQ = 3
    End Sub
 
    Private Sub rbAPI_Version2_KnowledgeBase_Call_CheckedChanged(sender As System.Object, e As System.EventArgs) Handles rbAPI_Version2_KnowledgeBase_Call.CheckedChanged
        My.Settings.current_API_REQ = 4
    End Sub
 
    Private Sub rbAPI_Version2_Detection_Data_CheckedChanged(sender As System.Object, e As System.EventArgs) Handles rbAPI_Version2_Detection_Data.CheckedChanged
        My.Settings.current_API_REQ = 5
    End Sub
 
    Private Sub cmdClearList_Click(sender As System.Object, e As System.EventArgs) Handles cmdClearList.Click
        lstWebMsgs.Items.Clear()
    End Sub
 
End Class