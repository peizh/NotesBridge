const Notes = Application("Notes");
for (let i = 1; i <= 3; i++) {
    const f = Notes.Folder({name: `Test Folder ${i}`});
    Notes.folders.push(f);
    for (let j = 1; j <= 2; j++) {
        const n = Notes.Note({name: `Note ${j} in Folder ${i}`, body: `Body ${j}`});
        f.notes.push(n);
    }
}
