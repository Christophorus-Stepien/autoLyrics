//=============================================================================
//  AUTOLYRICS v2.0 - Plugin for MuseScore 4.5
//
//  Step 1d: Multi-staff UI (dynamic first note detection)
//
//  Author: AI Assistant
//  License: GNU GPL v3
//=============================================================================

import MuseScore 3.0
import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2
import Qt.labs.platform 1.1

MuseScore {
    id: autoLyrics
    
    menuPath: "Plugins.AutoLyrics 2.0"
    description: "Automatically assign lyrics via MusicXML processing"
    version: "2.0"
    requiresScore: true
    pluginType: "dialog"
    
    width: 900
    height: 700
    
    // =========================================================================
    // MODELS
    // =========================================================================
    
    ListModel {
        id: staffListModel
    }
    
    ListModel {
        id: selectedStaffModel
    }
    
    // =========================================================================
    // PROPERTIES
    // =========================================================================
    
    property var staffConfigs: ({})      // Konfiguracja dla każdej pięciolinii
    property var measureMap: ({})
    property int totalMeasures: 100
    property string logText: ""
    property string exportPath: ""
    
    // =========================================================================
    // LOGGING
    // =========================================================================
    
    function log(msg) {
        console.log(msg);
        logText += msg + "\n";
        logArea.text = logText;
    }
    
    function clearLog() {
        logText = "";
        logArea.text = "";
    }
    
    // =========================================================================
    // INITIALIZATION
    // =========================================================================
    
    Component.onCompleted: {
        log("=== AutoLyrics v2.0 Starting ===");
        if (curScore) {
            buildMeasureMap();
            buildStaffList();
        } else {
            log("No score open!");
        }
    }
    
    // =========================================================================
    // BUILD MEASURE MAP
    // =========================================================================
    
    function buildMeasureMap() {
        log("Building measure map...");
        measureMap = {};
        totalMeasures = 0;
        
        if (!curScore) return;
        
        var cursor = curScore.newCursor();
        cursor.rewind(0);
        
        var measureNum = 0;
        
        do {
            if (!cursor.measure) break;
            
            measureNum++;
            var startTick = cursor.tick;
            var numerator = 4;
            var denominator = 4;
            
            if (cursor.measure.timesigActual) {
                numerator = cursor.measure.timesigActual.numerator;
                denominator = cursor.measure.timesigActual.denominator;
            }
            
            var ticksPerBeat = Math.round(1920 / denominator);
            var measureDuration = ticksPerBeat * numerator;
            
            measureMap[measureNum] = {
                startTick: startTick,
                endTick: startTick + measureDuration,
                numerator: numerator,
                denominator: denominator,
                ticksPerBeat: ticksPerBeat
            };
            
        } while (cursor.nextMeasure());
        
        totalMeasures = measureNum;
        log("Total measures: " + totalMeasures);
    }
    
    function getMeasureNumberAtTick(tick) {
        for (var m = 1; m <= totalMeasures; m++) {
            var info = measureMap[m];
            if (info && tick >= info.startTick && tick < info.endTick) {
                return m;
            }
        }
        return totalMeasures > 0 ? totalMeasures : 1;
    }
    
    function getBeatsInMeasure(measureNum) {
        var info = measureMap[measureNum];
        if (info) {
            return info.numerator;
        }
        return 4;
    }
    
    function getBeatAtTick(tick, measureNum) {
        var mInfo = measureMap[measureNum];
        if (mInfo) {
            var tickInMeasure = tick - mInfo.startTick;
            var beatNum = Math.floor(tickInMeasure / mInfo.ticksPerBeat) + 1;
            return Math.min(beatNum, mInfo.numerator);
        }
        return 1;
    }
    
    // =========================================================================
    // FIND FIRST NOTE - wywoływane dynamicznie przy każdej zmianie
    // =========================================================================
    
    function findFirstNoteInVoice(staffIdx, voiceIdx) {
        if (!curScore) {
            return { found: false, measure: 1, beat: 1, tick: 0 };
        }
        
        var cursor = curScore.newCursor();
        cursor.staffIdx = staffIdx;
        cursor.voice = voiceIdx;
        cursor.rewind(0);
        
        while (cursor.segment) {
            var element = cursor.element;
            if (element && element.type === Element.CHORD) {
                var tick = cursor.tick;
                var measureNum = getMeasureNumberAtTick(tick);
                var beatNum = getBeatAtTick(tick, measureNum);
                
                return {
                    found: true,
                    measure: measureNum,
                    beat: beatNum,
                    tick: tick
                };
            }
            cursor.next();
        }
        
        return { found: false, measure: 1, beat: 1, tick: 0 };
    }
    
    // =========================================================================
    // BUILD STAFF LIST
    // =========================================================================
    
    function buildStaffList() {
        log("Building staff list...");
        staffListModel.clear();
        selectedStaffModel.clear();
        staffConfigs = {};
        
        if (!curScore) {
            log("No score");
            return;
        }
        
        var globalStaffIdx = 0;
        
        for (var p = 0; p < curScore.parts.length; p++) {
            var part = curScore.parts[p];
            var partName = "Part " + (p + 1);
            
            try {
                if (part.longName && part.longName !== "") {
                    partName = part.longName;
                } else if (part.shortName && part.shortName !== "") {
                    partName = part.shortName;
                }
            } catch (e) {}
            
            var numStavesInPart = 1;
            try {
                var tracks = part.endTrack - part.startTrack;
                numStavesInPart = Math.floor(tracks / 4);
                if (numStavesInPart < 1) numStavesInPart = 1;
            } catch (e) {}
            
            for (var s = 0; s < numStavesInPart; s++) {
                var displayName = partName;
                if (numStavesInPart > 1) {
                    displayName = partName + " (Staff " + (s+1) + ")";
                }
                
                // Dodaj do ListModel
                staffListModel.append({
                    staffIndex: globalStaffIdx,
                    staffName: displayName,
                    isSelected: false
                });
                
                // Inicjalizuj konfigurację z domyślnymi wartościami
                // (będzie zaktualizowana przy zaznaczeniu)
                staffConfigs[globalStaffIdx] = {
                    voice: 0,
                    verse: 0,
                    measure: 1,
                    beat: 1,
                    maxBeat: 4,
                    customText: ""
                };
                
                log("  Staff " + globalStaffIdx + ": " + displayName);
                globalStaffIdx++;
            }
        }
        
        log("Found " + staffListModel.count + " staves");
        selectedCountLabel.text = "No staves selected";
    }
    
    // =========================================================================
    // STAFF SELECTION
    // =========================================================================
    
    function toggleStaff(index, selected) {
        if (index < 0 || index >= staffListModel.count) return;
        
        staffListModel.setProperty(index, "isSelected", selected);
        var staffIdx = staffListModel.get(index).staffIndex;
        var staffName = staffListModel.get(index).staffName;
        
        log("Staff " + staffIdx + " (" + staffName + "): " + (selected ? "selected" : "deselected"));
        
        // Jeśli zaznaczamy, znajdź pierwszą nutę dla aktualnego voice
        if (selected) {
            updateFirstNoteForStaff(staffIdx);
        }
        
        rebuildSelectedList();
    }
    
    function updateFirstNoteForStaff(staffIdx) {
        var config = staffConfigs[staffIdx];
        if (!config) return;
        
        // Odśwież measureMap przed szukaniem (partytura mogła się zmienić)
        buildMeasureMap();
        
        var noteInfo = findFirstNoteInVoice(staffIdx, config.voice);
        
        if (noteInfo.found) {
            config.measure = noteInfo.measure;
            config.beat = noteInfo.beat;
            config.maxBeat = getBeatsInMeasure(noteInfo.measure);
            log("  -> First note found: m." + config.measure + " beat " + config.beat);
        } else {
            config.measure = 1;
            config.beat = 1;
            config.maxBeat = getBeatsInMeasure(1);
            log("  -> No notes found in voice " + (config.voice + 1));
        }
    }
    
    function rebuildSelectedList() {
        selectedStaffModel.clear();
        
        for (var i = 0; i < staffListModel.count; i++) {
            var item = staffListModel.get(i);
            if (item.isSelected) {
                var cfg = staffConfigs[item.staffIndex];
                selectedStaffModel.append({
                    staffIndex: item.staffIndex,
                    staffName: item.staffName,
                    voice: cfg ? cfg.voice : 0,
                    verse: cfg ? cfg.verse : 0,
                    measure: cfg ? cfg.measure : 1,
                    beat: cfg ? cfg.beat : 1,
                    maxBeat: cfg ? cfg.maxBeat : 4,
                    customText: cfg ? cfg.customText : ""
                });
            }
        }
        
        selectedCountLabel.text = selectedStaffModel.count > 0 
            ? selectedStaffModel.count + " staff(s) selected"
            : "No staves selected";
    }
    
    function updateStaffConfig(staffIdx, property, value) {
        if (!staffConfigs[staffIdx]) return;
        
        staffConfigs[staffIdx][property] = value;
        
        // Jeśli zmieniono voice, znajdź pierwszą nutę dla nowego voice
        if (property === "voice") {
            log("Voice changed to " + (value + 1) + " for staff " + staffIdx);
            updateFirstNoteForStaff(staffIdx);
            rebuildSelectedList();
        }
        
        // Jeśli zmieniono measure, zaktualizuj maxBeat
        if (property === "measure") {
            var maxBeat = getBeatsInMeasure(value);
            staffConfigs[staffIdx].maxBeat = maxBeat;
            
            if (staffConfigs[staffIdx].beat > maxBeat) {
                staffConfigs[staffIdx].beat = maxBeat;
            }
            
            rebuildSelectedList();
        }
    }
    
    // =========================================================================
    // PROCESS
    // =========================================================================
    
    function processLyrics() {
        clearLog();
        log("=== Processing Lyrics ===");
        
        var mainText = lyricsInput.text.trim();
        if (mainText === "") {
            log("ERROR: No lyrics text entered");
            return;
        }
        
        if (selectedStaffModel.count === 0) {
            log("ERROR: No staves selected");
            return;
        }
        
        log("Main text: " + mainText.substring(0, 50) + (mainText.length > 50 ? "..." : ""));
        log("Selected staves: " + selectedStaffModel.count);
        log("");
        
        for (var i = 0; i < selectedStaffModel.count; i++) {
            var item = selectedStaffModel.get(i);
            var staffIdx = item.staffIndex;
            var config = staffConfigs[staffIdx];
            
            var textToUse = config.customText.trim() !== "" ? config.customText : mainText;
            
            log("--- Staff " + staffIdx + ": " + item.staffName + " ---");
            log("  Voice: " + (config.voice + 1));
            log("  Verse: " + (config.verse + 1));
            log("  Start: m." + config.measure + " beat " + config.beat);
            log("  Text: " + textToUse.substring(0, 30) + (textToUse.length > 30 ? "..." : ""));
        }
        
        log("");
        log("=== Step 1 Complete ===");
        log("Next step: MusicXML export");
    }

    // =========================================================================
    // MUSICXML EXPORT
    // =========================================================================

    function toLocalFile(url) {
        if (!url) return "";
        var path = url.toString();
        if (path.indexOf("file://") === 0) {
            return path.replace("file://", "");
        }
        return path;
    }

    function buildNotesForStaffVoice(staffIdx, voiceIdx) {
        var notesByMeasure = {};
        if (!curScore) return notesByMeasure;

        var cursor = curScore.newCursor();
        cursor.staffIdx = staffIdx;
        cursor.voice = voiceIdx;
        cursor.rewind(0);

        while (cursor.segment) {
            var element = cursor.element;
            if (element && element.type === Element.CHORD) {
                var tick = cursor.tick;
                var measureNum = getMeasureNumberAtTick(tick);
                if (!notesByMeasure[measureNum]) {
                    notesByMeasure[measureNum] = [];
                }
                if (element.notes && element.notes.length > 0) {
                    var note = element.notes[0];
                    notesByMeasure[measureNum].push({
                        pitch: note.pitch
                    });
                }
            }
            cursor.next();
        }

        return notesByMeasure;
    }

    function pitchToStepAlterOctave(pitch) {
        var steps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"];
        var alters = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0];
        var pc = pitch % 12;
        var step = steps[pc];
        var alter = alters[pc];
        var octave = Math.floor(pitch / 12) - 1;
        return { step: step, alter: alter, octave: octave };
    }

    function buildMusicXml() {
        buildMeasureMap();

        var xml = [];
        xml.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        xml.push("<score-partwise version=\"3.1\">");
        xml.push("  <part-list>");

        for (var i = 0; i < selectedStaffModel.count; i++) {
            var item = selectedStaffModel.get(i);
            var partId = "P" + (i + 1);
            xml.push("    <score-part id=\"" + partId + "\">");
            xml.push("      <part-name>" + item.staffName + "</part-name>");
            xml.push("    </score-part>");
        }

        xml.push("  </part-list>");

        for (var p = 0; p < selectedStaffModel.count; p++) {
            var staffItem = selectedStaffModel.get(p);
            var staffIdx = staffItem.staffIndex;
            var config = staffConfigs[staffIdx];
            var partIdValue = "P" + (p + 1);
            var notesByMeasure = buildNotesForStaffVoice(staffIdx, config.voice);

            xml.push("  <part id=\"" + partIdValue + "\">");

            for (var m = 1; m <= totalMeasures; m++) {
                xml.push("    <measure number=\"" + m + "\">");

                if (m === 1) {
                    xml.push("      <attributes>");
                    xml.push("        <divisions>1</divisions>");
                    xml.push("        <time>");
                    xml.push("          <beats>" + getBeatsInMeasure(1) + "</beats>");
                    xml.push("          <beat-type>4</beat-type>");
                    xml.push("        </time>");
                    xml.push("        <clef>");
                    xml.push("          <sign>G</sign>");
                    xml.push("          <line>2</line>");
                    xml.push("        </clef>");
                    xml.push("      </attributes>");
                }

                var notesInMeasure = notesByMeasure[m] || [];
                if (notesInMeasure.length === 0) {
                    xml.push("      <note>");
                    xml.push("        <rest/>");
                    xml.push("        <duration>1</duration>");
                    xml.push("        <type>quarter</type>");
                    xml.push("      </note>");
                } else {
                    for (var n = 0; n < notesInMeasure.length; n++) {
                        var noteInfo = notesInMeasure[n];
                        var pitchInfo = pitchToStepAlterOctave(noteInfo.pitch);
                        xml.push("      <note>");
                        xml.push("        <pitch>");
                        xml.push("          <step>" + pitchInfo.step + "</step>");
                        if (pitchInfo.alter !== 0) {
                            xml.push("          <alter>" + pitchInfo.alter + "</alter>");
                        }
                        xml.push("          <octave>" + pitchInfo.octave + "</octave>");
                        xml.push("        </pitch>");
                        xml.push("        <duration>1</duration>");
                        xml.push("        <type>quarter</type>");
                        xml.push("      </note>");
                    }
                }

                xml.push("    </measure>");
            }

            xml.push("  </part>");
        }

        xml.push("</score-partwise>");
        return xml.join("\n");
    }

    function exportMusicXml(filePath) {
        if (!curScore) {
            log("ERROR: No score open!");
            return;
        }
        if (selectedStaffModel.count === 0) {
            log("ERROR: No staves selected");
            return;
        }

        var finalPath = filePath || exportPath;
        if (!finalPath || finalPath === "") {
            log("ERROR: No export path selected");
            return;
        }

        var xmlContent = buildMusicXml();
        var file = new QFile(finalPath);
        if (!file.open(QIODevice.WriteOnly | QIODevice.Truncate)) {
            log("ERROR: Cannot open file: " + finalPath);
            return;
        }

        var out = new QTextStream(file);
        out.writeString(xmlContent);
        file.close();

        log("MusicXML exported to: " + finalPath);
    }
    
    // =========================================================================
    // USER INTERFACE
    // =========================================================================
    
    Rectangle {
        anchors.fill: parent
        color: "#f5f5f5"
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            
            // Header
            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    text: "AutoLyrics v2.0 - Multi-Staff"
                    font.bold: true
                    font.pixelSize: 16
                    color: "#333"
                }
                
                Item { Layout.fillWidth: true }
                
                Button {
                    text: "Refresh Score"
                    onClicked: {
                        clearLog();
                        log("=== Refreshing ===");
                        if (curScore) {
                            buildMeasureMap();
                            buildStaffList();
                        } else {
                            log("No score open!");
                        }
                    }
                }
                
                Button {
                    text: "Clear Log"
                    onClicked: clearLog()
                }
            }
            
            Rectangle {
                Layout.fillWidth: true
                height: 2
                color: "#2196F3"
            }
            
            // Main content
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                
                // Left column
                ColumnLayout {
                    Layout.preferredWidth: 450
                    Layout.fillHeight: true
                    spacing: 8
                    
                    // Staff selection header
                    Text {
                        text: "Select Staves:"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    
                    // Staff list with checkboxes
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        color: "#ffffff"
                        border.color: "#ddd"
                        
                        ListView {
                            id: staffListView
                            anchors.fill: parent
                            anchors.margins: 5
                            clip: true
                            spacing: 2
                            model: staffListModel
                            
                            delegate: Rectangle {
                                width: staffListView.width
                                height: 24
                                color: model.isSelected ? "#e3f2fd" : "transparent"
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 5
                                    anchors.rightMargin: 5
                                    spacing: 8
                                    
                                    CheckBox {
                                        id: staffCheckBox
                                        checked: model.isSelected
                                        onClicked: {
                                            toggleStaff(index, checked);
                                        }
                                    }
                                    
                                    Text {
                                        Layout.fillWidth: true
                                        text: model.staffName
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var newState = !model.isSelected;
                                                toggleStaff(index, newState);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Text {
                        id: selectedCountLabel
                        text: "No staves selected"
                        font.pixelSize: 11
                        color: "#666"
                    }
                    
                    // Main lyrics
                    Text {
                        text: "Main Lyrics Text:"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 100
                        color: "#ffffff"
                        border.color: "#ddd"
                        
                        TextArea {
                            id: lyricsInput
                            anchors.fill: parent
                            anchors.margins: 2
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: 11
                            selectByMouse: true
                            placeholderText: "Enter lyrics here... (use ~ for melisma)"
                        }
                    }
                    
                    // Selected staves config
                    Text {
                        text: "Configure Selected Staves:"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#fafafa"
                        border.color: "#ddd"
                        
                        ListView {
                            id: selectedStaffListView
                            anchors.fill: parent
                            anchors.margins: 5
                            clip: true
                            spacing: 8
                            model: selectedStaffModel
                            
                            delegate: Rectangle {
                                width: selectedStaffListView.width - 10
                                height: configLayout.height + 12
                                color: "#ffffff"
                                border.color: "#ccc"
                                radius: 4
                                x: 5
                                
                                property int staffIdx: model.staffIndex
                                
                                ColumnLayout {
                                    id: configLayout
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 6
                                    spacing: 4
                                    
                                    Text {
                                        text: model.staffName
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: "#2196F3"
                                    }
                                    
                                    GridLayout {
                                        columns: 4
                                        columnSpacing: 6
                                        rowSpacing: 2
                                        
                                        Text { text: "Voice:"; font.pixelSize: 10 }
                                        ComboBox {
                                            Layout.preferredWidth: 60
                                            font.pixelSize: 9
                                            model: ["1", "2", "3", "4"]
                                            currentIndex: staffConfigs[staffIdx] ? staffConfigs[staffIdx].voice : 0
                                            onActivated: {
                                                updateStaffConfig(staffIdx, "voice", currentIndex);
                                            }
                                        }
                                        
                                        Text { text: "Verse:"; font.pixelSize: 10 }
                                        ComboBox {
                                            Layout.preferredWidth: 60
                                            font.pixelSize: 9
                                            model: ["1","2","3","4","5","6","7","8","9","10"]
                                            currentIndex: staffConfigs[staffIdx] ? staffConfigs[staffIdx].verse : 0
                                            onActivated: {
                                                updateStaffConfig(staffIdx, "verse", currentIndex);
                                            }
                                        }
                                        
                                        Text { text: "Measure:"; font.pixelSize: 10 }
                                        SpinBox {
                                            Layout.preferredWidth: 70
                                            font.pixelSize: 9
                                            from: 1
                                            to: Math.max(1, totalMeasures)
                                            value: model.measure
                                            editable: true
                                            onValueModified: {
                                                updateStaffConfig(staffIdx, "measure", value);
                                            }
                                        }
                                        
                                        Text { text: "Beat:"; font.pixelSize: 10 }
                                        SpinBox {
                                            Layout.preferredWidth: 60
                                            font.pixelSize: 9
                                            from: 1
                                            to: model.maxBeat
                                            value: Math.min(model.beat, model.maxBeat)
                                            editable: true
                                            onValueModified: {
                                                updateStaffConfig(staffIdx, "beat", value);
                                            }
                                        }
                                    }
                                    
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        
                                        Text { 
                                            text: "Custom:"; 
                                            font.pixelSize: 10 
                                        }
                                        
                                        TextField {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 22
                                            font.pixelSize: 9
                                            placeholderText: "(empty = use main text)"
                                            text: model.customText
                                            onTextChanged: {
                                                updateStaffConfig(staffIdx, "customText", text);
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Empty state
                            Text {
                                anchors.centerIn: parent
                                visible: selectedStaffModel.count === 0
                                text: "Select staves above to configure"
                                font.pixelSize: 11
                                font.italic: true
                                color: "#999"
                            }
                        }
                    }
                    
                    // Process button
                    Button {
                        text: "Process Lyrics"
                        Layout.alignment: Qt.AlignRight
                        highlighted: true
                        onClicked: processLyrics()
                    }

                    Button {
                        text: "Export MusicXML"
                        Layout.alignment: Qt.AlignRight
                        onClicked: {
                            if (!curScore) {
                                log("ERROR: No score open!");
                                return;
                            }
                            if (selectedStaffModel.count === 0) {
                                log("ERROR: No staves selected");
                                return;
                            }
                            exportDialog.open();
                        }
                    }
                }
                
                // Right column - Log
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 5
                    
                    Text {
                        text: "Debug Log:"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#1e1e1e"
                        border.color: "#333"
                        
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 8
                            contentHeight: logArea.height
                            clip: true
                            
                            TextEdit {
                                id: logArea
                                width: parent.width
                                wrapMode: TextEdit.Wrap
                                font.pixelSize: 10
                                font.family: "Consolas, monospace"
                                color: "#00ff00"
                                readOnly: true
                                selectByMouse: true
                                text: ""
                            }
                        }
                    }
                    
                    RowLayout {
                        spacing: 10
                        
                        Button {
                            text: "Copy Log"
                            onClicked: {
                                logArea.selectAll();
                                logArea.copy();
                                logArea.deselect();
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Text {
                            text: "Step 1/5: Multi-staff UI"
                            font.pixelSize: 10
                            color: "#666"
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: "Export MusicXML"
        nameFilters: ["MusicXML (*.musicxml)", "MusicXML (*.xml)"]
        fileMode: FileDialog.SaveFile
        onAccepted: {
            exportPath = toLocalFile(exportDialog.file);
            exportMusicXml(exportPath);
        }
    }
}
