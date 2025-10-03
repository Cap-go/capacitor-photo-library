import { PhotoLibrary } from '@capgo/capacitor-photo-library';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    PhotoLibrary.echo({ value: inputValue })
}
