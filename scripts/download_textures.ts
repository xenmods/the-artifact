import fs from 'fs'
import path from 'path'
import unzip from 'unzip-stream'
import https from 'https'

const DEST_DIR = path.join(process.cwd(), 'public', 'textures')

async function fetchJSON(url: string) {
  const res = await fetch(url)
  return res.json()
}

async function downloadAndExtract(url: string, destPath: string) {
  console.log(`Downloading ${url} to ${destPath}...`)
  return new Promise((resolve, reject) => {
    https.get(url, (response) => {
      if (response.statusCode === 302 || response.statusCode === 301) {
        // Handle redirect
        downloadAndExtract(response.headers.location!, destPath).then(resolve).catch(reject)
        return
      }
      
      response.pipe(unzip.Extract({ path: destPath }))
        .on('close', resolve)
        .on('error', reject)
    })
  })
}

async function getMaterial(query: string, name: string) {
  console.log(`Searching for ${query}...`)
  // Using v2 API, querying for 1K JPGs
  const searchUrl = `https://ambientcg.com/api/v2/full_json?type=Material&id=${query}`
  const data = await fetchJSON(searchUrl)
  
  if (!data.foundAssets || data.foundAssets.length === 0) {
    console.error(`No assets found for ${query}`)
    return
  }
  
  const asset = data.foundAssets[0]
  const assetId = asset.assetId
  console.log(`Found ${assetId}. Getting download links...`)
  
  const downloadLink = `https://ambientcg.com/get?file=${assetId}_1K-JPG.zip`
  console.log(`Download link: ${downloadLink}`)
  
  const destPath = path.join(DEST_DIR, name)
  fs.mkdirSync(destPath, { recursive: true })
  
  await downloadAndExtract(downloadLink, destPath)
  console.log(`Successfully extracted ${name}!`)
}

async function run() {
  fs.mkdirSync(DEST_DIR, { recursive: true })
  
  // Install unzip-stream if not present
  try {
    require.resolve('unzip-stream')
  } catch (e) {
    console.log('Installing unzip-stream...')
    Bun.spawnSync(['bun', 'add', '-d', 'unzip-stream', '@types/unzip-stream'])
  }

  await getMaterial('Marble015', 'marble015')
  
  console.log('All textures downloaded!')
}

run().catch(console.error)
