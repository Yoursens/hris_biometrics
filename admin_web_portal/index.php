<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HRIS Admin Master Portal</title>
    <!-- Tailwind CSS -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Firebase SDK -->
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore-compat.js"></script>
    <!-- jQuery for AJAX -->
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
</head>
<body class="bg-slate-900 text-white font-sans">

    <div class="flex h-screen">
        <!-- Sidebar -->
        <div class="w-64 bg-slate-800 border-r border-slate-700 p-6 flex flex-col">
            <h1 class="text-2xl font-bold text-emerald-400 mb-8 flex items-center">
                <span class="mr-2">🛡️</span> HRIS MASTER
            </h1>
            <nav class="space-y-4 flex-1">
                <a href="#" class="block p-3 rounded-lg bg-emerald-500/10 text-emerald-400 font-bold border border-emerald-500/20">Dashboard</a>
                <a href="#" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Employees</a>
                <a href="#" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Reports</a>
            </nav>
            <div class="p-4 bg-slate-900/50 rounded-xl border border-slate-700/50">
                <p class="text-xs text-slate-500 uppercase font-bold mb-1">Status</p>
                <div class="flex items-center text-emerald-400 text-sm">
                    <span class="relative flex h-2 w-2 mr-2">
                        <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                        <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                    </span>
                    Real-time Connected
                </div>
            </div>
        </div>

        <!-- Main Content -->
        <div class="flex-1 flex flex-col overflow-hidden">
            <!-- Header -->
            <header class="bg-slate-800 border-b border-slate-700 p-4 px-8 flex justify-between items-center">
                <div class="relative w-96">
                    <input type="text" placeholder="Search employee..." class="w-full bg-slate-900 border border-slate-700 rounded-full py-2 px-10 text-sm focus:outline-none focus:border-emerald-500">
                    <span class="absolute left-4 top-2.5">🔍</span>
                </div>
                <div class="flex items-center space-y-0 space-x-4">
                    <span class="text-sm font-medium">Administrator</span>
                    <div class="w-10 h-10 rounded-full bg-emerald-500 flex items-center justify-center font-bold">AD</div>
                </div>
            </header>

            <!-- Table Section -->
            <main class="flex-1 overflow-y-auto p-8">
                <div class="flex justify-between items-end mb-6">
                    <div>
                        <h2 class="text-3xl font-bold">Attendance Master Logs</h2>
                        <p class="text-slate-400 text-sm mt-1">Real-time sync from Mobile App via Firebase & MySQL</p>
                    </div>
                    <div class="bg-slate-800 rounded-lg p-1 border border-slate-700 flex text-sm">
                        <button class="px-4 py-1.5 bg-slate-700 rounded-md shadow-sm">All Logs</button>
                        <button class="px-4 py-1.5 hover:bg-slate-700 rounded-md transition-all">Today</button>
                    </div>
                </div>

                <!-- Statistics Grid -->
                <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-400 text-sm font-bold uppercase tracking-wider mb-2">Active Now</div>
                        <div class="text-4xl font-black text-emerald-400" id="stat-active">0</div>
                    </div>
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-400 text-sm font-bold uppercase tracking-wider mb-2">Total Clock-Ins</div>
                        <div class="text-4xl font-black text-blue-400" id="stat-total">0</div>
                    </div>
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-400 text-sm font-bold uppercase tracking-wider mb-2">Late Entries</div>
                        <div class="text-4xl font-black text-rose-400" id="stat-late">0</div>
                    </div>
                </div>

                <!-- Table -->
                <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-2xl">
                    <table class="w-full text-left border-collapse">
                        <thead>
                            <tr class="bg-slate-900/50 border-b border-slate-700 text-slate-400 text-xs font-bold uppercase">
                                <th class="p-4 px-6">Employee</th>
                                <th class="p-4">Time In</th>
                                <th class="p-4">Time Out</th>
                                <th class="p-4">Date</th>
                                <th class="p-4 text-center">Status</th>
                            </tr>
                        </thead>
                        <tbody id="attendance-table-body">
                            <!-- Data injected here via JavaScript -->
                        </tbody>
                    </table>
                </div>
            </main>
        </div>
    </div>

    <script>
        // --- FIREBASE CONFIGURATION ---
        const firebaseConfig = {
            apiKey: "AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg",
            authDomain: "week-9-activity-53484.firebaseapp.com",
            projectId: "week-9-activity-53484",
            storageBucket: "week-9-activity-53484.firebasestorage.app",
            messagingSenderId: "1095102475957",
            appId: "1:1095102475957:web:45a4624634e83b53e4d8fc",
            measurementId: "G-605G4TDLCX"
        };

        firebase.initializeApp(firebaseConfig);
        const db = firebase.firestore();

        // --- REAL-TIME LISTENER ---
        db.collection('clock_ins').orderBy('saved_at', 'desc').onSnapshot((snapshot) => {
            const tableBody = $('#attendance-table-body');
            tableBody.empty();

            let total = 0;
            let late = 0;

            snapshot.forEach((doc) => {
                const data = doc.data();
                total++;
                if(data.status === 'late') late++;

                const row = `
                    <tr class="border-b border-slate-700/50 hover:bg-slate-700/30 transition-colors">
                        <td class="p-4 px-6">
                            <div class="flex items-center">
                                <div class="w-8 h-8 rounded-lg bg-slate-700 flex items-center justify-center mr-3 text-emerald-400 font-bold">
                                    ${data.employee_name ? data.employee_name.charAt(0) : 'E'}
                                </div>
                                <div>
                                    <div class="font-bold">${data.employee_name || 'Unknown'}</div>
                                    <div class="text-xs text-slate-500">${data.employee_id}</div>
                                </div>
                            </div>
                        </td>
                        <td class="p-4 font-mono text-sm text-emerald-400">${data.time_in}</td>
                        <td class="p-4 font-mono text-sm text-slate-500">${data.time_out || '--:--'}</td>
                        <td class="p-4 text-sm">${data.date}</td>
                        <td class="p-4 text-center">
                            <span class="px-3 py-1 rounded-full text-[10px] font-black uppercase tracking-widest ${data.status === 'late' ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30' : 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'}">
                                ${data.status}
                            </span>
                        </td>
                    </tr>
                `;
                tableBody.append(row);

                // --- SYNC TO MYSQL VIA AJAX ---
                syncToMySQL(doc.id, data);
            });

            $('#stat-total').text(total);
            $('#stat-late').text(late);
            $('#stat-active').text(total - late); // Simplified for demo
        });

        function syncToMySQL(firebaseId, data) {
            $.ajax({
                url: 'sync_attendance.php',
                type: 'POST',
                data: {
                    firebase_id: firebaseId,
                    employee_id: data.employee_id,
                    employee_name: data.employee_name,
                    time_in: data.time_in,
                    time_out: data.time_out,
                    date: data.date,
                    status: data.status
                },
                success: function(response) {
                    console.log("MySQL Sync Status:", response);
                }
            });
        }
    </script>
</body>
</html>
