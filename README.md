🍔 MJ POS System

A modern, real-time Point of Sale (POS) system built for cafes and restaurants. Features instant synchronization between Cashier and Kitchen stations, back-office management, and sales tracking.

✨ Features

🖥️ Cashier Station

Visual Menu: Grid layout with product images and prices.

Cart Management: Add items, adjust quantities, and add special instructions (e.g., "No sugar").

Waiting Numbers: Assign customer numbers (1-50) with auto-check for availability.

Real-Time "Busy" List: Instantly sees which numbers are currently in the kitchen.

Payments: Supports Cash (with quick-add buttons) and Card recording.

🍳 Kitchen Display System (KDS)

Live Order Sync: Orders appear instantly without refreshing.

Workflow: Track status from New (Grey) → Cooking (Orange) → Ready (Green).

Timers: Shows how long ago an order was placed (e.g., "5m ago").

Auto-Clear: Marking an order as "Complete" instantly frees up the waiting number for the Cashier.

📊 Back Office

Product Management: Add, edit, and delete items.

Category Management: Organize menu items.

Sales History: View past receipts and daily totals.

🚀 Tech Stack

Framework: Flutter (Web & Mobile)

Backend: Supabase (PostgreSQL)

State Management: setState + StreamBuilders (Real-time architecture)

Deployment: Vercel
