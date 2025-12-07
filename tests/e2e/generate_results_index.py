#!/usr/bin/env python3
"""
Generate an index.html page that links to all e2e test results.
This provides a single entry point to browse all test executions.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path


def find_all_results(base_dir: Path):
    """Find all results.json and results.html files in e2e test directories."""
    results = []
    
    # Find all e2e-* directories
    for exec_dir in sorted(base_dir.glob("e2e-*"), reverse=True):
        if not exec_dir.is_dir():
            continue
        
        exec_id = exec_dir.name
        exec_timestamp = exec_id.replace("e2e-", "")
        
        # Parse timestamp
        try:
            dt = datetime.strptime(exec_timestamp, "%Y%m%d-%H%M%S")
            formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            formatted_time = exec_timestamp
        
        # Find provider results
        providers = []
        for provider_dir in sorted(exec_dir.iterdir()):
            if not provider_dir.is_dir():
                continue
            
            results_json = provider_dir / "results.json"
            results_html = provider_dir / "results.html"
            
            if results_json.exists() or results_html.exists():
                provider_info = {
                    'name': provider_dir.name,
                    'has_json': results_json.exists(),
                    'has_html': results_html.exists(),
                    'json_path': str(results_json.relative_to(base_dir)) if results_json.exists() else None,
                    'html_path': str(results_html.relative_to(base_dir)) if results_html.exists() else None,
                }
                
                # Extract summary from results.json if available
                if results_json.exists():
                    try:
                        with open(results_json, 'r') as f:
                            data = json.load(f)
                            provider_info['total'] = data.get('total_tests', 0)
                            provider_info['passed'] = data.get('passed', 0)
                            provider_info['failed'] = data.get('failed', 0)
                            provider_info['duration'] = data.get('total_time', 0)
                    except Exception:
                        pass
                
                providers.append(provider_info)
        
        if providers:
            results.append({
                'exec_id': exec_id,
                'timestamp': formatted_time,
                'providers': providers
            })
    
    return results


def generate_index_html(base_dir: Path, results):
    """Generate the index.html file."""
    
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
<meta http-equiv="refresh" content="60">
<title>Exasol E2E Test Results Index</title>
<style>
body {
    font-family: Arial, sans-serif;
    margin: 2rem;
    background-color: #f5f5f5;
}
h1 {
    color: #333;
    border-bottom: 3px solid #4CAF50;
    padding-bottom: 0.5rem;
}
.header-info {
    background: #fff;
    padding: 1rem;
    border-radius: 5px;
    margin-bottom: 2rem;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
.execution {
    background: white;
    margin-bottom: 1.5rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    overflow: hidden;
}
.exec-header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 1rem 1.5rem;
    cursor: pointer;
    display: flex;
    justify-content: space-between;
    align-items: center;
}
.exec-header:hover {
    background: linear-gradient(135deg, #5568d3 0%, #653a8b 100%);
}
.exec-header h2 {
    margin: 0;
    font-size: 1.2rem;
}
.exec-timestamp {
    font-size: 0.9rem;
    opacity: 0.9;
}
.providers {
    padding: 1rem 1.5rem;
}
.provider {
    display: flex;
    align-items: center;
    padding: 0.75rem;
    margin: 0.5rem 0;
    background: #f9f9f9;
    border-radius: 5px;
    border-left: 4px solid #4CAF50;
}
.provider.has-failures {
    border-left-color: #f44336;
}
.provider-name {
    font-weight: bold;
    min-width: 120px;
    color: #333;
}
.provider-stats {
    flex: 1;
    display: flex;
    gap: 1rem;
    font-size: 0.9rem;
}
.stat {
    padding: 0.25rem 0.5rem;
    border-radius: 3px;
    background: #e0e0e0;
}
.stat.passed {
    background: #c8e6c9;
    color: #2e7d32;
}
.stat.failed {
    background: #ffcdd2;
    color: #c62828;
}
.provider-links {
    display: flex;
    gap: 0.5rem;
}
.provider-links a {
    padding: 0.4rem 0.8rem;
    background: #2196F3;
    color: white;
    text-decoration: none;
    border-radius: 4px;
    font-size: 0.85rem;
    transition: background 0.2s;
}
.provider-links a:hover {
    background: #1976D2;
}
.no-results {
    padding: 2rem;
    text-align: center;
    color: #666;
    background: white;
    border-radius: 8px;
}
.collapsed {
    display: none;
}
.toggle-icon {
    transition: transform 0.3s;
}
.toggle-icon.expanded {
    transform: rotate(90deg);
}
</style>
<script>
function toggleExecution(execId) {
    const content = document.getElementById('exec-' + execId);
    const icon = document.getElementById('icon-' + execId);
    if (content.classList.contains('collapsed')) {
        content.classList.remove('collapsed');
        icon.classList.add('expanded');
    } else {
        content.classList.add('collapsed');
        icon.classList.remove('expanded');
    }
}

document.addEventListener('DOMContentLoaded', () => {
    // Expand the first (most recent) execution by default
    const firstExec = document.querySelector('.providers');
    if (firstExec) {
        firstExec.classList.remove('collapsed');
        const firstIcon = document.querySelector('.toggle-icon');
        if (firstIcon) {
            firstIcon.classList.add('expanded');
        }
    }
});
</script>
</head>
<body>
<h1>Exasol E2E Test Results</h1>
<div class="header-info">
    <p><strong>Total Executions:</strong> """ + str(len(results)) + """</p>
    <p><strong>Last Updated:</strong> """ + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + """</p>
    <p><small>This page auto-refreshes every 60 seconds</small></p>
</div>
"""
    
    if not results:
        html_content += """
<div class="no-results">
    <h2>No test results found</h2>
    <p>Run e2e tests to see results here</p>
</div>
"""
    else:
        for exec_data in results:
            exec_id = exec_data['exec_id']
            timestamp = exec_data['timestamp']
            providers = exec_data['providers']
            
            html_content += f"""
<div class="execution">
    <div class="exec-header" onclick="toggleExecution('{exec_id}')">
        <div>
            <h2>{exec_id}</h2>
            <div class="exec-timestamp">{timestamp}</div>
        </div>
        <div class="toggle-icon" id="icon-{exec_id}">▶</div>
    </div>
    <div class="providers collapsed" id="exec-{exec_id}">
"""
            
            for provider in providers:
                has_failures = provider.get('failed', 0) > 0
                failure_class = ' has-failures' if has_failures else ''
                
                html_content += f"""
        <div class="provider{failure_class}">
            <div class="provider-name">{provider['name']}</div>
            <div class="provider-stats">
"""
                
                if 'total' in provider:
                    html_content += f"""
                <span class="stat">Total: {provider['total']}</span>
                <span class="stat passed">Passed: {provider['passed']}</span>
                <span class="stat failed">Failed: {provider['failed']}</span>
                <span class="stat">Duration: {provider['duration']:.1f}s</span>
"""
                
                html_content += """
            </div>
            <div class="provider-links">
"""
                
                if provider['has_html']:
                    html_content += f"""
                <a href="{provider['html_path']}" target="_blank">View Report</a>
"""
                
                if provider['has_json']:
                    html_content += f"""
                <a href="{provider['json_path']}" target="_blank">JSON</a>
"""
                
                html_content += """
            </div>
        </div>
"""
            
            html_content += """
    </div>
</div>
"""
    
    html_content += """
</body>
</html>
"""
    
    index_file = base_dir / "index.html"
    with open(index_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    return index_file


def main():
    """Main entry point."""
    if len(sys.argv) > 1:
        base_dir = Path(sys.argv[1])
    else:
        base_dir = Path("./tmp/tests")
    
    if not base_dir.exists():
        print(f"Directory not found: {base_dir}")
        sys.exit(1)
    
    results = find_all_results(base_dir)
    index_file = generate_index_html(base_dir, results)
    
    print(f"Generated index: {index_file}")
    print(f"Found {len(results)} test execution(s)")


if __name__ == "__main__":
    main()
