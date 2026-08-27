"""
Student management endpoints.

NOTE: main.py does `from routes import buses, tracking, students, schools`
and the folder structure in the guide lists this file, but the guide's
walkthrough never writes its contents out (STEP 10 only shows the
Flutter registration screen and the React admin StudentList component,
both of which talk to Supabase directly). This is a straightforward
CRUD module written to match the same patterns used in routes/buses.py
so the app in the guide runs end to end.
"""
from fastapi import APIRouter
from database import supabase
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

class StudentCreate(BaseModel):
    school_id: str
    student_name: str
    parent_name: Optional[str] = None
    parent_phone: Optional[str] = None
    parent_email: Optional[str] = None
    bus_id: Optional[str] = None
    stop_id: Optional[str] = None

class StudentAssign(BaseModel):
    bus_id: str
    stop_id: str

@router.get("/")
def get_students(school_id: str):
    """Get all students for a school, with their assigned bus + stop."""
    result = supabase.table("students")\
        .select("*, buses(bus_number), stops(stop_name)")\
        .eq("school_id", school_id)\
        .execute()
    return result.data

@router.post("/")
def register_student(student: StudentCreate):
    """Register a student (used by the parent registration screen)."""
    result = supabase.table("students").insert(student.dict()).execute()
    return result.data[0]

@router.put("/{student_id}/assign")
def assign_student(student_id: str, assignment: StudentAssign):
    """Admin assigns a student to a bus + stop (STEP 10.3)."""
    result = supabase.table("students")\
        .update({"bus_id": assignment.bus_id, "stop_id": assignment.stop_id})\
        .eq("id", student_id)\
        .execute()
    return result.data[0] if result.data else {"message": "Student not found"}

@router.delete("/{student_id}")
def delete_student(student_id: str):
    """Remove a student record."""
    supabase.table("students").delete().eq("id", student_id).execute()
    return {"message": "Student deleted"}
