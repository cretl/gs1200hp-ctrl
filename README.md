# gs1200hp-ctrl-ng
<h2>TL;DR</h2>
<p>
Control the PoE ports of a Zyxel GS1200-5HP switch with a simple Bash script.<br />
Only Bash, curl and printf are needed.
</p>

<h2>Info</h2>
<p>
With this simple Bash script you can control the PoE ports of a Zyxel GS1200-5HP v2 PoE switch.<br />
The script <b>may</b> also work with hardware revision v1.<br />
Tested firmware: V2.00(ABKN.1)C0 (latest available firmware at 2021/11/01).
</p>

<h3>Script</h3>
<h4>Dependencies</h4>
<p>
Bash, curl and printf.
Just install with e.g. <code>apt install bash curl printf</code>
</p>

<h4>Installation</h4>
<ol>
<li>Just copy the script to a file.</li>
<li>Edit the settings part in the script.</li>
<li>Make the file executeable (e.g., with chmod +x).</li>
<li>Run the script: <code>./gs1200c.sh {on|off|status} {1|2|3|4|all}</code></li>
</ol>

<h4>Script actions</h4>
<p>The script uses the web interface of the switch to set the currently active PoE ports.<br />
It does perform the following steps:<br />
<ol>
  <li>Login to the switch's web interface with the supplied IP address and password. If the firmware version requires an "encryption" of the password it is done before the login.</li>
  <li>The script saves the session cookie, which is required to perform the following steps.</li>
  <li>Analyze the currently active ports by getting the http://${switchIP}/port_state_data.js file.</li>
  <li>Getting the active PoE ports by posting to the http://$switchIP/port_state_set.cgi file.</li>
  <li>After completing the script does log out to be able to login again.</li>
</ol>
</p>

<h4>Background</h4>
<p>
The 4 PoE ports of the switch have the following numerical values:<br />
port1=1;	port2=2;	port3=4;	port4=8<br />
The currently active PoE ports are calculates by combining these values.<br />
Examples:  0=[off]; 1=[1 on]; 3=[1&2 on]; 5=[1&2&3 on]; 15=[1&2&3&4 on];<br />
There are 16 combinations possible.
</p>

<h4>Important notes</h4>
<ul>
  <li>After logging in and while a user session is active the switch blocks any other connection attempt to the HTTP port. You must successfully log out to be able to login again. If you fail to successfully logout, you must either restart (powercycle) the switch or wait for the session timeout (about 5 minutes).</li>
  <li>The script is currently only tested with the firmware version <b>V2.00(ABKN.0)C0</b>. Newer versions may break the functionality.</li>
</ul>
