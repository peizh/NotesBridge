const Notes = Application("Notes");
const folders = Notes.folders();
console.log("Found " + folders.length + " folders.");
for (let i = 0; i < folders.length; i++) {
    const f = folders[i];
    console.log("Checking folder: " + f.name());
    try {
        const notes = f.notes();
        console.log("  Notes count: " + notes.length);
    } catch (e) {
        console.log("  Error: " + e.message);
    }
}
