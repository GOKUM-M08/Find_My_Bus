// NOTE: not given in the guide (which starts at src/App.jsx), but a
// create-react-app project needs an entry point to mount App into the
// DOM. Standard CRA boilerplate.
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'

const root = ReactDOM.createRoot(document.getElementById('root'))
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
