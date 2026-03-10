const Notes = Application("Notes");
const note = Notes.notes[0];
const id = note.id();

try {
    const fetched = Notes.notes.byId(id);
    console.log("Success byId on Notes: " + fetched.name());
} catch (e) {
    console.log("Error Notes.notes.byId: " + e.message);
}

const folder = note.container();
try {
    const fetchedFolder = Notes.folders.byId(folder.id());
    console.log("Success byId on Folders: " + fetchedFolder.name());
} catch (e) {
    console.log("Error Notes.folders.byId: " + e.message);
}
