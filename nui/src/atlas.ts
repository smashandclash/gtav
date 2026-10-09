// The atlas page (a DUI the table samples): paint it, then say so in the title.

import { paintAtlas } from './atlas-paint';

const canvas = document.getElementById('atlas') as HTMLCanvasElement;
void paintAtlas(canvas).then(() => (document.title = 'atlas ready'));
