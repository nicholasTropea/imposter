import { createBrowserRouter } from 'react-router';

import Home from './pages/Home.tsx';
import CreateGame from './pages/CreateGame.tsx';


export const router = createBrowserRouter([
    {
        path : '/',
        Component : Home
    },
    {
        path : '/create-game',
        Component : CreateGame
    }
]);