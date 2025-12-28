Use Windows.pkg
Use DFClient.pkg
Use File_dlg.pkg
Use seq_chnl.pkg
Use cJsonObject.pkg
Use cSelectFolderDialog.pkg

Use SectorFunctions.pkg
Use MyIniFile.pkg

Use Amadeus.pkg

Deferred_View Activate_oMainProcess for ;
Object oMainProcess is a dbView

    Set Border_Style to Border_Thick
    Set Size to 162 300
    Set Location to 2 2
    Set Label to "Main Scanning Process"
    Set piMinSize to 162 300
    Set piMaxSize to 162 300
    
    Property Integer[] piaIURPointers
    Property String psLogFolder
    Property String psDataFolder
    
    Object oSelectLogFolderDg is a cSelectFolderDialog
    End_Object

    Object oScannerIniFile is a cIniFile

        Procedure SetDefaultFileName
            String sProgramPath

            Get psProgramPath of (phoWorkspace(ghoApplication)) to sProgramPath
            Set psFileName         to (sProgramPath + "\Scanner.ini")
            Set psPrivate_FileName to (sProgramPath + "\Scanner.ini")
        End_Procedure

        Function IniFileExists Returns Boolean
            Boolean bExists

            Send SetDefaultFileName
            Get KeyExists "GENERAL" "DefaultDataFolder" to bExists
            If (not(bExists)) ;
                Send WriteString "GENERAL" "DefaultDataFolder" ".\RawData\" // Create an INI file if needed
            Function_Return (True) // Will always exist now
        End_Function

        Function IniFileSectionExists String sSection Returns Boolean
            Boolean bExists

            Send SetDefaultFileName
            Get SectionExists sSection to bExists
            Function_Return (bExists)
        End_Function

        Function IniFileKeyExists String sSection String sKey Returns Boolean
            Boolean bExists

            Send SetDefaultFileName
            Get KeyExists sSection sKey to bExists
            Function_Return (bExists)
        End_Function

        Function ReadBoolean String sSection String sKey Boolean bDefault Returns Boolean
            String sTemp sDefault
            
            If (bDefault) ;
                Move "True" to sDefault
            Else ;
                Move "False" to sDefault
            Move (ReadString(Self, sSection, sKey, sDefault)) to sTemp
            If (Uppercase(sTemp) = "TRUE" or sTemp = '1' or Left(Uppercase(sTemp), 1) = 'Y') ;
                Function_Return (True)
            Else ;
                Function_Return (False)
        End_Function

        Procedure WriteBoolean String sSection String sKey Boolean bValue
            String sValue
            
            If (bValue) ;
                Move "True" to sValue
            Else ;
                Move "False" to sValue
            Send WriteString sSection sKey sValue
        End_Procedure

    End_Object

    Object oOpenDialog is a OpenDialog
    
        // Call up the Open Dialog via:
    //    Get Show_Dialog {of object} to BooleanVariable
    
    End_Object

    Function GenerateAmadeusJson tAmadeusAIR tRecord Returns String
        Handle hoJson
        String sResult
        
        Get Create (RefClass(cJsonObject)) to hoJson
        Set peWhiteSpace of hoJson to jpWhitespace_Pretty // jpWhitespace_Spaced option?
        Send DataTypeToJson of hoJson tRecord

        If (Checked_State(oSparseJsonCb)) Begin
            // Remove 'null' members here including empty arrays
            Send RemoveNullJSONMembers hoJson 0 0 0
//            Send StripEmptyMembers hoJson
        End

        Get Stringify of hoJson to sResult
        Send Destroy of hoJson
        Function_Return sResult
    End_Function

    Function PreScan_InputFile String sInputFile Returns Integer[]
        Integer[] iaResults
        Integer iRow iChannel iPosition iHoldPosition itempInt
        String sChar sTemp sBlock
        Boolean bErr bPanelWasRunning

        If (Value(oInputFileNameForm) = '') Begin
            Send UserError "Inport file name must be set" "Operator Error"
            Move True to bErr
        End
        Else Begin
            Set Caption_Text       of ghoStatusPanel to ("Reading Data File")
            Set Title_Text         of ghoStatusPanel to (String(sInputFile))
            Set Message_Text       of ghoStatusPanel to ""
            Set Allow_Cancel_State of ghoStatusPanel to True // Allow interrupt
            Move (Active_State(ghoStatusPanel)) to bPanelWasRunning
            If (not(bPanelWasRunning)) Begin
                Send Start_StatusPanel of ghoStatusPanel // Pop it up on the screen
            End

            Move (Seq_New_Channel()) to iChannel
            Direct_Input channel iChannel sInputFile
            Read_Block channel iChannel sChar 1
            If (not(bErr)) Begin
                Set_Channel_Position iChannel to 0 // Set back to the top of file
                While (not(SeqEof))
                    Get_Channel_Position iChannel to iHoldPosition
                    Read_Block channel iChannel sBlock 9 // Read 9 chars
            		// Logic to determine the beginning of a record
		            // Be careful to test well, this data can occur within the data in theory
            		If (mid(sBlock, 4, 1) = "AIR-" and ;
            			mid(sBlock, 3, 5) = "BLK"  and ;
            			mid(sBlock, 2, 8) = "20") Begin
                        // We found a start of record for Amadeus
                        Move iHoldposition to iaResults[-1] // Append pointer to the end of the array
                        Move (iHoldPosition + 9) to iHoldPosition // We can jump past this known start of record text
                        Move (SizeOfArray(iaResults)) to iTempInt
                        If (itempInt < 10 or Mod(itempInt, 10) = 0) ;
                            Send Update_StatusPanel of ghoStatusPanel ("Record:" * String(iTempint)) // Update status
         			End
                    Else Begin
                        Increment iHoldPosition // Only move forward one byte
                    End
                    Set_Channel_Position iChannel to iHoldPosition // Test again at the next character

                    If (Check_Stop_Process()) ; // Check fo stop request
                        Move True to SeqEof // Force break out of loop
                Loop // Not SeqEof
            End
            Close_Input channel iChannel
            Send Seq_Release_Channel iChannel

            If (not(bPanelWasRunning)) Begin
                Set Allow_Cancel_State of ghoStatusPanel to False // Disallow interrupt as a default
                Send Stop_StatusPanel of ghoStatusPanel
            End
        End
        Set Value of oIURCountForm to (SizeOfArray(iaResults))
        Function_Return (iaResults)
    End_Function

    Function Pull_One_Record String sInputFile Integer iStartPosition Integer iEndPosition Returns String[]
        String[] saRecordLines
        String[] saBlank
        String sLine
        Integer iChannel iHoldPosition
        Boolean bPanelWasRunning bReading
        
        Set Caption_Text       of ghoStatusPanel to ("Parsing Data File")
        Set Title_Text         of ghoStatusPanel to (String(sInputFile))
        Set Message_Text       of ghoStatusPanel to ""
        Set Allow_Cancel_State of ghoStatusPanel to True // Allow interrupt
        Move (Active_State(ghoStatusPanel)) to bPanelWasRunning
        If (not(bPanelWasRunning)) Begin
            Send Start_StatusPanel of ghoStatusPanel // Pop it up on the screen
        End

        Move saBlank to saRecordLines // Blank the holding array
        Move (Seq_New_Channel()) to iChannel
        Direct_Input channel iChannel sInputFile

        Set_Channel_Position iChannel to iStartPosition
        Move True to bReading
        Repeat
            Readln sLine
            Move sLine to saRecordLines[-1] // Append to record line array
            Get_Channel_Position iChannel to iHoldPosition
            If (SeqEof);
                Move False to bReading
            If (bReading) ;
                Move (iHoldPosition < iEndPosition) to bReading // Are we at or past the next record's position?
        Until (not(bReading) or SeqEof)

        Close_Input channel iChannel
        Send Seq_Release_Channel iChannel
        If (not(bPanelWasRunning)) Begin
            Set Allow_Cancel_State of ghoStatusPanel to False // Disallow interrupt as a default
            Send Stop_StatusPanel of ghoStatusPanel
        End

        Function_Return saRecordLines
    End_Function

    Function SizeOfFile String sFileName Returns Integer
        Integer iRtnVal iChannel

        Move (Seq_New_Channel()) to iChannel
        Append_Output channel iChannel sFileName
        Get_Channel_Position iChannel to iRtnVal
        Close_Input iChannel
        Send Seq_Release_Channel iChannel
        Function_Return iRtnVal
    End_Function

    Object oIURCountForm is a Form
        Set Location to 145 38
        Set Size to 12 28
        Set Entry_State to False
        Set Form_Datatype to Mask_Numeric_Window
        Set Form_Mask to "###,##0"
        Set Label to "Records"
        Set Label_Col_Offset to 3
        Set Label_Justification_Mode to JMode_Right
    End_Object

    Object oMainTabDialog is a TabDialog
        Set Location to 2 2
        Set Size to 137 296
        Set peAnchors to anAll

        Object oProcessPage is a TabPage
            Set Label to 'Process Session'

            Object oInputFileNameForm is a Form
                Set Label to "Input File"
                Set Size to 12 245
                Set Location to 5 38
                Set Label_Col_Offset to 3
                Set Label_Justification_Mode to JMode_Right
                Set Prompt_Button_Mode to pb_PromptOn
                Set peAnchors to anTopLeftRight
        
                Procedure Activating
                    If (Value(Self) = '') Begin
                        Set Value to (psDataFolder(Self))
                    End

                    Forward Send Activating
                End_Procedure
        
        //        Procedure CheckFileExtension String sExtension
        //            String sFileName sFileExtension
        //            Integer iPos
        //
        //            Get Value to sFileName
        //            Get DRPathFindExtension sFileName to sFileExtension
        //            If (trim(sFileExtension) <> '') Begin // Has an extension, remove it
        //                Move (Pos(sFileExtension, sFileName)) to iPos // Pointer to start of the extension characters
        //                Move (Left(sFileName, iPos - 1)) to sFileName // File name up to the extension
        //            End
        //            Move (sFileName - sExtension) to sFileName // Append the new extension
        //            Set Value to sFileName
        //        End_Procedure
        
                Procedure Prompt
                    Boolean bOk
                    String sFileName sFilePath sDataPath sFileTitle
        
                    Get Value to sFileName
        
                    If (sFileName <> '') Begin
                        Set File_Name of oOpenDialog to sFileName
        //                Get ExtractFilePath sFileName to sFilePath
        //                Get ExtractFileName sFileName to sFileTitle
                        Set File_Title of oOpenDialog to sFileTitle // Default for the name in the windows open dialog
                    End
                
                    Set Initial_Folder of oOpenDialog to sFilePath
        
                    Get Show_Dialog of oOpenDialog to bOk
                    If (bOk) Begin
                        Get File_Name of oOpenDialog to sFileName
                        Set Value to sFileName
        //                Send CheckFileExtension ".json"
        //                Send WriteSettings of oATG24_Settings '*' "ATG24" "IMPORTALFETTA" "LASTFILE" sFileName ''
                    End
        
                End_Procedure
        
            End_Object

            Object oPreScanButton is a Button
                Set Location to 46 15
                Set Label to '&Pre-Scan'
            
                Procedure OnClick
                    Boolean bErr
                    Integer[] iaIURPointers
                    Integer[] iBlank
        
                    Get piaIURPointers to iaIURPointers // Connect local to global property
                    Move iBlank to iaIURPointers // Clear any old data
        
                    Get PreScan_InputFile (Value(oInputFileNameForm)) to iaIURPointers // Scan the input file to get pointers to the start of each IUR
                    Move (SizeOfArray(iaIURPointers) < 1) to bErr // Should not be empty
                    
                    If (bErr) Begin
                        Send UserError "Unknown error in Inputing this file" "Data File Error"
                    End
                    Else Begin
                        Set piaIURPointers to iaIURPointers // Connect local to back to global property
                        Set Value of oIURCountForm to (SizeOfArray(iaIURPointers))
        
        //                Send Info_Box ("There are" * String(SizeOfArray(iaIURPointers)) * "Records read.") "Confirmation"
                    End
                End_Procedure
            
            End_Object
            Object oTestButton is a Button
                Set Location to 46 70
                Set Label to '&Test'
            
                Procedure OnClick
                    Integer[] iaIURPointers
                    String[] saRecordLines
                    String[] saBlank
                    Integer iRow iMax iStart iEnd
        
                    Get piaIURPointers to iaIURPointers // Connect local to global property
        
                    Move (SizeOfArray(iaIURPointers)) to iMax
                    For iRow from 0 to (iMax - 1)
                        Move saBlank to saRecordLines // Clear any prior data
                        Move iaIURPointers[iRow] to iStart
                        If (iRow < iMax - 1) ;
                            Move (iaIURPointers[iRow + 1]) to iEnd
                        Else ;
                            Move (SizeOfFile(Self, Value(oInputFileNameForm))) to iEnd // EOF indicator
        
                        Get Pull_One_Record (Value(oInputFileNameForm)) iStart iEnd to saRecordLines
        
                    Loop
        
                End_Procedure
            
            End_Object

            Object oSplitButton is a Button
                Set Location to 46 129
                Set Label to 'S&plit'
            
                Procedure OnClick
                    Integer[] iaIURPointers
                    String[] saRecordLines
                    String[] saBlank
                    Integer iRow iMax iStart iEnd
                    Integer iChannel
                    Integer iRecPtr
                    String sOutputFileName sFilePath
                    Boolean bPanelWasRunning
        
                    Get piaIURPointers to iaIURPointers // Connect local to global property
        
                    Set Caption_Text       of ghoStatusPanel to ("Splitting Data File")
                    Set Title_Text         of ghoStatusPanel to (Value(oInputFileNameForm))
                    Set Message_Text       of ghoStatusPanel to ""
                    Set Allow_Cancel_State of ghoStatusPanel to True // Allow interrupt
                    Move (Active_State(ghoStatusPanel)) to bPanelWasRunning
                    If (not(bPanelWasRunning)) Begin
                        Send Start_StatusPanel of ghoStatusPanel // Pop it up on the screen
                    End
        
                    If (SizeOfArray(iaIURPointers) = 0) Begin
                        // Need to read in the file
                        Get PreScan_InputFile (Value(oInputFileNameForm)) to iaIURPointers // Scan the input file to get pointers to the start of each IUR
                    End
        
                    Move (ExtractFilePath(Value(oInputFileNameForm))) to sFilePath
                    Move (SizeOfArray(iaIURPointers)) to iMax
                    For iRow from 0 to (iMax - 1)
                        Move saBlank to saRecordLines // Clear any prior data
                        Move iaIURPointers[iRow] to iStart
                        If (iRow < iMax - 1) ;
                            Move (iaIURPointers[iRow + 1]) to iEnd
                        Else ;
                            Move (SizeOfFile(Self, Value(oInputFileNameForm))) to iEnd // EOF indicator
        
                        Get Pull_One_Record (Value(oInputFileNameForm)) iStart iEnd to saRecordLines
        
                        // Prepare an output file
                        Move (String(iRow + 1)) to sOutputFileName
                        Move (Lpad_With(sOutputFileName, 6, '0')) to sOutputFileName
                        Move (String(sOutputFileName) - ".PNR") to sOutputFileName
                        If (iRow < 10 or Mod(iRow, 10) = 0) ;
                            Send Update_StatusPanel of ghoStatusPanel ("IUR File:" * String(sOutputFileName)) // Update status
                        Move (String(sFilePath) - String(sOutputFileName)) to sOutputFileName
        
                        Move (Seq_New_Channel()) to iChannel
                        Direct_Output channel iChannel sOutputFileName
                        For iRecPtr from 0 to (SizeOfArray(saRecordLines) - 1)
                            Writeln channel iChannel saRecordLines[iRecPtr]
                        Loop
                        Close_Output iChannel
                        Send Seq_Release_Channel iChannel
        
                        If (Check_Stop_Process()) ; // Check fo stop request
                            Move imax to iRow // Force break out of loop
                    Loop
        
                    If (not(bPanelWasRunning)) Begin
                        Set Allow_Cancel_State of ghoStatusPanel to False // Disallow interrupt as a default
                        Send Stop_StatusPanel of ghoStatusPanel
                    End
        
                End_Procedure
            
            End_Object

            Object oParseButton is a Button
                Set Location to 46 191
                Set Label to 'P&arse'
            
                Procedure OnClick
                    Integer[] iaIURPointers
                    String[] saRecordLines
                    String[] saBlank
                    Integer iRow iMax iStart iEnd iPos
                    Integer iChannel
                    Integer iRecPtr
                    String sOutputFileName sFilePath sFileExtension
                    String sAmadeusJSON
                    Boolean bPanelWasRunning
                    tAmadeusAIR AmadeusAIR
        
                    Get piaIURPointers to iaIURPointers // Connect local to global property
        
                    Set Caption_Text       of ghoStatusPanel to ("Parsing Data File")
                    Set Title_Text         of ghoStatusPanel to (Value(oInputFileNameForm))
                    Set Message_Text       of ghoStatusPanel to ""
                    Set Allow_Cancel_State of ghoStatusPanel to True // Allow interrupt
                    Move (Active_State(ghoStatusPanel)) to bPanelWasRunning
                    If (not(bPanelWasRunning)) Begin
                        Send Start_StatusPanel of ghoStatusPanel // Pop it up on the screen
                    End
        
                    If (SizeOfArray(iaIURPointers) = 0) Begin
                        // Need to read in the file
                        Get PreScan_InputFile (Value(oInputFileNameForm)) to iaIURPointers // Scan the input file to get pointers to the start of each IUR
                    End
        
                    Move (ExtractFilePath(Value(oInputFileNameForm))) to sFilePath
                    Move (SizeOfArray(iaIURPointers)) to iMax
                    For iRow from 0 to (iMax - 1)
                        Move saBlank to saRecordLines // Clear any prior data
                        Move iaIURPointers[iRow] to iStart
                        If (iRow < iMax - 1) ;
                            Move (iaIURPointers[iRow + 1]) to iEnd
                        Else ;
                            Move (SizeOfFile(Self, Value(oInputFileNameForm))) to iEnd // EOF indicator
        
                        If (iRow < 10 or Mod(iRow, 10) = 0) ;
                            Send Update_StatusPanel of ghoStatusPanel ("Processing:" * String(iRow + 1) * "of" * String(iMax)) // Update status
                        Get Pull_One_Record (Value(oInputFileNameForm)) iStart iEnd to saRecordLines

                        // Process the record
                        Move (ParseAmadeusAIR(saRecordLines)) to AmadeusAIR
                                
                        // Prepare an output file.
                        // ToDo: Option for single output file or one file per record.
                        Move (ExtractFileName(Value(oInputFileNameForm))) to sOutputFileName
                        Move (RemoveExtensionFromFile(sOutputFileName)) to sOutputFileName
                        Move (String(sOutputFileName) - ".json") to sOutputFileName
                        Move (String(sFilePath) - String(sOutputFileName)) to sOutputFileName
                        // Open the file
                        Move (Seq_New_Channel()) to iChannel
                        If (iRow = 0) ;
                            Direct_Output channel iChannel sOutputFileName
                        Else ;
                            Append_Output channel iChannel sOutputFileName
                        
                        // Output the record
//                        For iRecPtr from 0 to (SizeOfArray(saRecordLines) - 1)
//                            Writeln channel iChannel saRecordLines[iRecPtr] // Output text version
//                        Loop

                        Move (GenerateAmadeusJson(Self, AmadeusAIR)) to sAmadeusJSON // Convert struct to json text
                        Writeln sAmadeusJSON

                        Close_Output iChannel
                        Send Seq_Release_Channel iChannel
        
                        If (Check_Stop_Process()) ; // Check fo stop request
                            Move imax to iRow // Force break out of loop
                    Loop
        
                    If (not(bPanelWasRunning)) Begin
                        Set Allow_Cancel_State of ghoStatusPanel to False // Disallow interrupt as a default
                        Send Stop_StatusPanel of ghoStatusPanel
                    End
        
                End_Procedure
            
            End_Object
        End_Object

        Object oConfigPage is a TabPage
            Set Label to 'Configuration'

            Object oSourceFolder is a Form
                Set Size to 12 239
                Set Location to 9 45
                Set Prompt_Button_Mode to PB_PromptOn
                Set peAnchors to anTopLeftRight
                Set Label to "Log Folder"
                Set Label_Justification_Mode to JMode_Right
                Set Label_Col_Offset to 3
        
                Procedure Activating
                    Set Value to (psLogfolder(Self))
                    Forward Send Activating
                End_Procedure
            
                Procedure Prompt
                    String sFolder
                    
                    Forward Send Prompt
        
                    Get SelectFolder of oSelectLogFolderDg "Select a Folder" (Value(Self)) to sFolder
                    If (sFolder <> "") Begin
                        Set Value of Self to sFolder // (sFolder - '\') // Append the back slash
                        Set psLogFolder of oMainProcess to sFolder // (sFolder - '\')
                    End
        
                End_Procedure
            End_Object

            Object oLogFileCb is a CheckBox
                Set Location to 29 45
                Set Size to 10 50
                Set Label to "Activate Log File"
            End_Object

            Object oSparseJsonCb is a CheckBox
                Set Location to 43 45
                Set Size to 10 50
                Set Label to "Sparse JSON format"
            End_Object

        End_Object

    End_Object

    Procedure InitializeFields
        String sTempStr sLogFolder

        Move (psHome(phoWorkspace(ghoApplication))) to sLogFolder // Default to the home folder of the application
        Move (ReadString(oScannerIniFile, "GENERAL", "LogFolder", sLogFolder)) to sLogFolder
        If (Right(sLogFolder, 1) = SysConf(SYSCONF_DIR_SEPARATOR)) ;
            Move (Left(sLogFolder, (Length(Trim(sLogFolder)) - 1))) to sLogFolder // Remove possible end slash
        Set psLogFolder to sLogFolder

        Move (ReadString(oScannerIniFile, "GENERAL", "DefaultDataFolder", sTempStr)) to sTempStr
        If (Right(sTempStr, 1) = SysConf(SYSCONF_DIR_SEPARATOR)) ;
            Move (Left(sTempStr, (Length(Trim(sTempStr)) - 1))) to sTempStr // Remove possible end slash
        Set psDataFolder to sTempStr

        Move (ReadString(oScannerIniFile, "GENERAL", "LastDataFile", sTempStr)) to sTempStr
        Set Value of oInputFileNameForm to sTempStr

        Set Checked_State of oLogFileCb to (ReadBoolean(oScannerIniFile, "GENERAL", "ActivateLogFile", False))
        Set Checked_State of oSparseJsonCb to (ReadBoolean(oScannerIniFile, "GENERAL", "SparseJSON", True))

    End_Procedure

    Procedure UpdateIniFields
        Send WriteString  of oScannerIniFile "GENERAL" "LastDataFile" (Value(oInputFileNameForm))
        Send WriteString  of oScannerIniFile "GENERAL" "DefaultDataFolder" (ExtractFilePath(Value(oInputFileNameForm)))
        Send WriteString  of oScannerIniFile "GENERAL" "LogFolder" (psLogFolder(oMainProcess))
        Send WriteBoolean of oScannerIniFile "GENERAL" "ActivateLogFile" (Checked_State(oLogFileCb))
        Send WriteBoolean of oScannerIniFile "GENERAL" "SparseJSON" (Checked_State(oSparseJsonCb))
    End_Procedure

    Procedure Activate
        If (IniFileExists(oScannerIniFile)) Begin
            Send InitializeFields
        End
        Forward Send Activate
    End_Procedure

    Procedure Deactivating
        Send UpdateIniFields
        Forward Send Deactivating
        Send Exit_Application // Leave the complete application
    End_Procedure

Cd_End_Object
